module Async::Cable
	class Executor
		class Timer < Data.define(:task)
			def shutdown = task.stop
		end

		def initialize(max_size: 1024)
			@semaphore = ::Async::Semaphore.new(max_size)
		end

		def post(task = nil, &block)
			task ||= block
			
			@semaphore.async(&task)
		end

		def timer(interval, &block)
			task = Async do
				loop do
					sleep(interval)
					block.call
				end
			end
			
			Timer.new(task)
		end

		def shutdown
			@executor.shutdown
		end
	end
end
