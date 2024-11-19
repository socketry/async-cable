# Benchmark

The basic benchmark compares connection and broadcast performance.

## Usage

First, install all the dependencies using `bundle install`.

Then, start a server, e.g.

```shell
$ cd benchmark/servers
$ bundle exec ./falcon.rb
```

Then, run `broadcast.rb`:

```
$ bundle exec ./broadcast.rb
Connected 5000 clients in 2.947s.
Amortized connection time: 0.589ms.
Broadcast 100 times to 5000 clients in 16.713s.
Amortized broadcast time: 0.033ms.
```

You can adjust the counts in the `benchmark.rb` script.

## Results

Broadcast benchmark, 5000 clients, 100 broadcasts:

| Server | Process | Compression | Connection Time     | Broadcast Time    |
|--------|---------|-------------|---------------------|-------------------|
| Puma   | 1       | No          | 0.67ms / connection | 0.04ms / message  |
| Falcon | 1       | No          | 0.56ms / connection | 0.03ms / message  |
| Falcon | 1       | Deflate     | 0.83ms / connection | 0.034ms / message |
