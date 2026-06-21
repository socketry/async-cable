# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "async"

module Async
	module Cable
		# Fiber-based replacement for `ActionCable::Server::ThreadedExecutor`.
		#
		# Action Cable uses an `#executor` to dispatch internal async work
		# (pub/sub callback invocations, heartbeat timers, periodic channel
		# timers) and broadcasts a small interface: `#post`, `#timer`,
		# `#shutdown`. Stock Rails backs this with a
		# {Concurrent::ThreadPoolExecutor}; under a fiber-scheduler-aware
		# server like Falcon every `#post` then bounces through an OS thread
		# unnecessarily.
		#
		# This executor instead spawns Async tasks. Tasks posted from inside
		# a reactor run on the caller's reactor (no thread hop). Tasks
		# posted or scheduled from outside a reactor run on a dedicated
		# reactor thread owned by the executor.
		class Executor
			# Create a new executor. The dedicated reactor thread is started
			# lazily on first use that needs it (timers, or `#post` from
			# outside a reactor).
			def initialize
				@mutex = ::Thread::Mutex.new
				@inbox = nil
				@thread = nil
			end
			
			# Run the given callable asynchronously. When called from inside
			# a reactor this spawns a fire-and-forget child task on the
			# current reactor; when called from outside a reactor this routes
			# the task to the executor's dedicated reactor thread. The return
			# value is the executor (matching
			# `ActionCable::Server::ThreadedExecutor#post`).
			# @parameter task [#call, nil] Callable to run; if nil, the block is used.
			def post(task = nil, &block)
				block ||= task
				
				if current = ::Async::Task.current?
					current.async{block.call}
				else
					inbox.push(proc{block.call})
				end
				
				return self
			end
			
			# Schedule a recurring timer. When called from inside a reactor
			# this spawns a child task on the current reactor; when called
			# from outside a reactor this routes the timer to the executor's
			# dedicated reactor thread.
			# @parameter interval [Numeric] Seconds between invocations.
			# @returns [Timer] A handle that responds to `#shutdown`.
			def timer(interval, &block)
				timer = Timer.new
				
				if current = ::Async::Task.current?
					timer.task = current.async do |inner|
						run_timer(inner, interval, block)
					end
					
					return timer
				end
				
				inbox = timer.inbox = self.inbox
				begin
					operation = proc do |task|
						timer.task = task.async do |inner|
							run_timer(inner, interval, block)
						end
					end
					
					inbox.push(operation)
				rescue ::ClosedQueueError
					# Executor is shutting down; match the best-effort
					# behaviour of posting work during shutdown.
				end
				
				return timer
			end
			
			# Stop the dedicated reactor thread (if any). Tasks posted to
			# the caller's reactor via `#post` are unaffected; their
			# lifetime is owned by the calling reactor.
			def shutdown
				@mutex.synchronize do
					return unless @thread
					@inbox.close
					@thread.join
					@thread = nil
					@inbox = nil
				end
			end
			
			# Handle returned from `#timer`. Wraps the underlying
			# `Async::Task` and exposes a thread-safe `#shutdown` matching
			# the `Concurrent::TimerTask` interface that callers expect.
			# Timers running on the dedicated reactor are cancelled through
			# the executor's inbox; timers running on the caller's reactor
			# are cancelled directly.
			class Timer
				attr_writer :inbox
				
				# Initialize an empty timer handle.
				def initialize
					@inbox = nil
					@mutex = ::Thread::Mutex.new
					@task = nil
				end
				
				# Set the underlying task. Called by the executor thread
				# once the timer has been scheduled.
				def task=(task)
					@mutex.synchronize{@task = task}
				end
				
				# Cancel the timer. Idempotent; safe to call from any thread
				# or fiber.
				def shutdown
					task = nil
					
					@mutex.synchronize do
						task = @task
						@task = nil
					end
					return unless task
					
					if inbox = @inbox
						begin
							inbox.push(proc{task.stop})
						rescue ::ClosedQueueError
							# Executor already shut down; the timer task was
							# stopped along with its parent reactor.
						end
					else
						task.stop
					end
				end
			end
			
			private
			
			def inbox
				@inbox || @mutex.synchronize{@inbox ||= start_thread}
			end
			
			def run_timer(task, interval, block)
				loop do
					task.sleep(interval)
					block.call
				end
			end
			
			def start_thread
				inbox = ::Thread::Queue.new
				
				@thread = ::Thread.new do
					::Thread.current.name = "async-cable executor"
					
					Sync do |task|
						while operation = inbox.pop
							operation.call(task)
						end
					end
				end
				
				return inbox
			end
		end
	end
end
