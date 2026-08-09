use std::future::Future;
use std::sync::{Arc, Mutex};

use tokio::sync::Notify;

use crate::MihomoError;

/// One cached value for the active backend, with in-flight request sharing.
/// Clearing a target also invalidates a request that finishes after release.
pub(crate) struct ActiveTargetCache<T> {
    state: Mutex<CacheState<T>>,
}

struct CacheState<T> {
    value: Option<(String, T)>,
    stale: bool,
    next: u64,
    active: Option<(String, u64, Arc<InFlight<T>>)>,
}

struct InFlight<T> {
    result: Mutex<Option<Result<T, MihomoError>>>,
    notify: Notify,
}

enum LoadAction<T> {
    Ready(T),
    Wait(Arc<InFlight<T>>),
    Start(u64, Arc<InFlight<T>>),
}

impl<T> Default for CacheState<T> {
    fn default() -> Self {
        Self {
            value: None,
            stale: false,
            next: 0,
            active: None,
        }
    }
}

impl<T: Clone> ActiveTargetCache<T> {
    pub(crate) fn new() -> Self {
        Self {
            state: Mutex::new(CacheState::default()),
        }
    }

    pub(crate) fn get(&self, key: &str) -> Option<T> {
        self.state
            .lock()
            .expect("active target cache poisoned")
            .value
            .as_ref()
            .filter(|(cached_key, _)| cached_key == key)
            .map(|(_, value)| value.clone())
    }

    pub(crate) async fn load<F, Fut>(
        &self,
        key: &str,
        force: bool,
        loader: F,
    ) -> Result<T, MihomoError>
    where
        F: FnOnce() -> Fut,
        Fut: Future<Output = Result<T, MihomoError>>,
    {
        let action = {
            let mut state = self.state.lock().expect("active target cache poisoned");
            if !force
                && !state.stale
                && let Some((_, value)) = state
                    .value
                    .as_ref()
                    .filter(|(cached_key, _)| cached_key == key)
            {
                LoadAction::Ready(value.clone())
            } else if let Some((_, _, in_flight)) = state
                .active
                .as_ref()
                .filter(|(active_key, _, _)| active_key == key)
            {
                LoadAction::Wait(Arc::clone(in_flight))
            } else {
                if state
                    .value
                    .as_ref()
                    .is_some_and(|(cached_key, _)| cached_key != key)
                {
                    state.value = None;
                    state.stale = false;
                }
                state.next = state.next.wrapping_add(1);
                let token = state.next;
                let in_flight = Arc::new(InFlight::new());
                state.active = Some((key.to_string(), token, Arc::clone(&in_flight)));
                LoadAction::Start(token, in_flight)
            }
        };
        let (token, in_flight) = match action {
            LoadAction::Ready(value) => return Ok(value),
            LoadAction::Wait(in_flight) => return in_flight.wait().await,
            LoadAction::Start(token, in_flight) => (token, in_flight),
        };
        let result = loader().await;
        let mut state = self.state.lock().expect("active target cache poisoned");
        let current = state
            .active
            .as_ref()
            .is_some_and(|(active_key, active_token, _)| {
                active_key == key && *active_token == token
            });
        if current {
            state.active = None;
            if let Ok(value) = &result {
                state.value = Some((key.to_string(), value.clone()));
                state.stale = false;
            }
        }
        drop(state);
        in_flight.complete(result.clone());
        result
    }

    pub(crate) fn clear(&self, key: &str) {
        let mut state = self.state.lock().expect("active target cache poisoned");
        if state
            .active
            .as_ref()
            .is_some_and(|(active_key, _, _)| active_key == key)
        {
            state.active = None;
        }
        if state
            .value
            .as_ref()
            .is_some_and(|(cached_key, _)| cached_key == key)
        {
            state.value = None;
            state.stale = false;
        }
    }

    pub(crate) fn invalidate(&self, key: &str) {
        let mut state = self.state.lock().expect("active target cache poisoned");
        if state
            .active
            .as_ref()
            .is_some_and(|(active_key, _, _)| active_key == key)
        {
            state.active = None;
        }
        if state
            .value
            .as_ref()
            .is_some_and(|(cached_key, _)| cached_key == key)
        {
            state.stale = true;
        }
    }
}

impl<T: Clone> InFlight<T> {
    fn new() -> Self {
        Self {
            result: Mutex::new(None),
            notify: Notify::new(),
        }
    }

    async fn wait(&self) -> Result<T, MihomoError> {
        loop {
            let notified = self.notify.notified();
            if let Some(result) = self
                .result
                .lock()
                .expect("active target load poisoned")
                .clone()
            {
                return result;
            }
            notified.await;
        }
    }

    fn complete(&self, result: Result<T, MihomoError>) {
        *self.result.lock().expect("active target load poisoned") = Some(result);
        self.notify.notify_waiters();
    }
}
