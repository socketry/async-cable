# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "async/cable/executor"
require "sus/fixtures/async"

describe Async::Cable::Executor do
	let(:executor) {subject.new}
	
	with "#post" do
		it "runs the block when called from outside a reactor" do
			completed = ::Thread::Queue.new
			executor.post{completed.push(true)}
			expect(completed.pop).to be == true
		ensure
			executor.shutdown
		end
		
		it "accepts a positional callable as well as a block" do
			completed = ::Thread::Queue.new
			executor.post(->{completed.push(:ok)})
			expect(completed.pop).to be == :ok
		ensure
			executor.shutdown
		end
		
		with "called from inside a reactor" do
			include Sus::Fixtures::Async::ReactorContext
			
			it "runs the block on the caller's reactor with no thread hop" do
				caller_thread = ::Thread.current
				completed = ::Thread::Queue.new
				
				executor.post do
					completed.push(::Thread.current)
				end
				
				expect(completed.pop).to be == caller_thread
			ensure
				executor.shutdown
			end
		end
	end
	
	with "#timer" do
		it "runs the block at the configured interval" do
			ticks = ::Thread::Queue.new
			timer = executor.timer(0.01){ticks.push(true)}
			
			3.times{ticks.pop}
			
			timer.shutdown
		ensure
			executor.shutdown
		end
		
		it "stops invoking the block after #shutdown" do
			ticks = ::Thread::Queue.new
			timer = executor.timer(0.01){ticks.push(true)}
			
			# Drain a couple of ticks so we know it started:
			2.times{ticks.pop}
			
			timer.shutdown
			
			# After shutdown, allow any in-flight tick to land then sample:
			sleep 0.05
			ticks.clear
			sleep 0.05
			expect(ticks).to be(:empty?)
		ensure
			executor.shutdown
		end
	end
	
	with "#shutdown" do
		it "is idempotent" do
			executor.shutdown
			executor.shutdown
		end
		
		it "stops the dedicated thread used by timers" do
			# A scheduled timer is what spins up the dedicated reactor thread:
			ticks = ::Thread::Queue.new
			timer = executor.timer(0.01){ticks.push(true)}
			ticks.pop
			
			thread = executor.instance_variable_get(:@thread)
			expect(thread).to be(:alive?)
			
			timer.shutdown
			executor.shutdown
			
			expect(thread).not.to be(:alive?)
		end
	end
end
