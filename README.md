If you are writing a new networked service, you are probably choosing between Go and async Rust. If you know about async Rust [footguns](https://tmandry.gitlab.io/blog/posts/making-async-reliable/) you might also consider sync Rust.

How do these languages compare in terms of CPU and RAM usage? Let's find out.

We'll use a simple TCP echo server as our benchmark. To get definitive a definitive answer for your specific project, you'd have to implement your service in all languages and compare. But we can get a sense of the performance characteristics of each technology by benchmarking a simple TCP echo server.

## Results

Let's start with the result and discuss methodology later.

