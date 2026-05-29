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
		# posted from outside a reactor — and all recurring timers — run on
		# a dedicated reactor thread owned by the executor.
		class Executor
			# Create a new executor. The dedicated reactor thread is started
			# lazily on first use that needs it (timers, or `#post` from
			# outside a reactor).
			def initialize
				@mutex = ::Mutex.new
				@inbox = nil
				@thread = nil
			end
			
			# Run the given callable asynchronously via `Async { ... }`. When
			# called from inside a reactor this spawns a fire-and-forget child
			# task on the current reactor; when called from outside `Async`
			# opens a transient reactor and runs the block to completion. The
			# return value is the executor (matching
			# `ActionCable::Server::ThreadedExecutor#post`).
			# @parameter task [#call, nil] Callable to run; if nil, the block is used.
			def post(task = nil, &block)
				block ||= task
				Async {block.call}
				self
			end
			
			# Schedule a recurring timer. The timer always runs on the
			# executor's dedicated reactor thread so its lifetime is
			# decoupled from any individual request reactor.
			# @parameter interval [Numeric] Seconds between invocations.
			# @returns [Timer] A handle that responds to `#shutdown`.
			def timer(interval, &block)
				timer = Timer.new(inbox)
				inbox.push([:timer, interval, block, timer])
				timer
			end
			
			# Stop the dedicated reactor thread (if any). Tasks posted to
			# the caller's reactor via `#post` are unaffected; their
			# lifetime is owned by the calling reactor.
			def shutdown
				@mutex.synchronize do
					return unless @thread
					@inbox.push(:shutdown)
					@thread.join
					@thread = nil
					@inbox = nil
				end
			end
			
			# Handle returned from `#timer`. Wraps the underlying
			# `Async::Task` and exposes a thread-safe `#shutdown` matching
			# the `Concurrent::TimerTask` interface that callers expect.
			# The cancel is routed back through the executor's inbox so it
			# always runs on the timer's own reactor (callers don't need to
			# be inside a reactor to call `#shutdown`).
			class Timer
				def initialize(inbox)
					@inbox = inbox
					@mutex = ::Mutex.new
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
					task = @mutex.synchronize do
						t = @task
						@task = nil
						t
					end
					return unless task
					
					begin
						@inbox.push([:stop_timer, task])
					rescue ::ClosedQueueError
						# Executor already shut down; the timer task was
						# stopped along with its parent reactor.
					end
				end
			end
			
			private
			
			def inbox
				@inbox || @mutex.synchronize{@inbox ||= start_thread}
			end
			
			def start_thread
				inbox = ::Thread::Queue.new
				@thread = ::Thread.new do
					::Thread.current.name = "async-cable executor"
					Sync do |task|
						while (command = inbox.pop)
							case command
							in [:timer, interval, callable, handle]
								handle.task = task.async do |inner|
									loop do
										inner.sleep(interval)
										callable.call
									end
								end
							in [:stop_timer, timer_task]
								timer_task.stop
							in :shutdown
								inbox.close
								break
							end
						end
					end
				end
				inbox
			end
		end
	end
end
