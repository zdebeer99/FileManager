//! Thread pools for file system work (spec 4.3). Nothing here runs on the
//! UI or main thread, and slow locations get their own pool so a hanging
//! network share can never hold up local folders.

use std::path::Path;
use std::thread;
use std::time::Duration;

use rayon::{ThreadPool, ThreadPoolBuilder};
use tokio::sync::oneshot;

use crate::platform;

pub struct IoPools {
    local: ThreadPool,
    slow: ThreadPool,
}

impl IoPools {
    pub fn new() -> Self {
        let cpus = thread::available_parallelism().map_or(4, |n| n.get());
        Self { local: build_pool("io-local", cpus.clamp(4, 16)), slow: build_pool("io-slow", 4) }
    }

    /// Runs `work` on the pool that matches the path.
    pub fn spawn(&self, path: &Path, work: impl FnOnce() + Send + 'static) {
        if platform::is_slow_path(path) {
            self.slow.spawn(work);
        } else {
            self.local.spawn(work);
        }
    }

    /// Runs `work` on the right pool and waits for its result, giving up
    /// after `timeout` (the work itself keeps going in the background).
    pub async fn run<T: Send + 'static>(
        &self,
        path: &Path,
        timeout: Duration,
        work: impl FnOnce() -> T + Send + 'static,
    ) -> Result<T, String> {
        let (tx, rx) = oneshot::channel();
        self.spawn(path, move || {
            let _ = tx.send(work());
        });
        match tokio::time::timeout(timeout, rx).await {
            Ok(Ok(value)) => Ok(value),
            Ok(Err(_)) => Err("The operation stopped unexpectedly.".into()),
            Err(_) => Err("Location not available: it did not respond in time.".into()),
        }
    }
}

fn build_pool(name: &'static str, threads: usize) -> ThreadPool {
    ThreadPoolBuilder::new()
        .num_threads(threads)
        .thread_name(move |i| format!("{name}-{i}"))
        // A failing task must never take the app down (NFR-REL-04).
        .panic_handler(|_| tracing::error!("a background file system task panicked"))
        .build()
        .expect("failed to start I/O threads")
}
