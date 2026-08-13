use std::collections::HashMap;
use std::future::Future;
use std::pin::Pin;
use std::sync::{Arc, Mutex as SyncMutex, OnceLock, Weak};

use tokio::sync::Mutex;

use crate::MihomoError;

use super::{SurgeControllerConnection, SurgeControllerTarget, target_key};

type UnarySlot = Arc<Mutex<Option<SurgeControllerConnection>>>;

fn connect_locks() -> &'static SyncMutex<HashMap<String, Weak<Mutex<()>>>> {
    static LOCKS: OnceLock<SyncMutex<HashMap<String, Weak<Mutex<()>>>>> = OnceLock::new();
    LOCKS.get_or_init(|| SyncMutex::new(HashMap::new()))
}

fn connect_lock(target: &SurgeControllerTarget) -> Arc<Mutex<()>> {
    let key = target_key(target);
    let mut locks = connect_locks()
        .lock()
        .expect("surge controller connect lock cache poisoned");
    locks.retain(|_, lock| lock.strong_count() > 0);
    if let Some(lock) = locks.get(&key).and_then(Weak::upgrade) {
        return lock;
    }
    let lock = Arc::new(Mutex::new(()));
    locks.insert(key, Arc::downgrade(&lock));
    lock
}

fn unary_sessions() -> &'static SyncMutex<HashMap<String, UnarySlot>> {
    static SESSIONS: OnceLock<SyncMutex<HashMap<String, UnarySlot>>> = OnceLock::new();
    SESSIONS.get_or_init(|| SyncMutex::new(HashMap::new()))
}

fn unary_slot(target: &SurgeControllerTarget) -> UnarySlot {
    unary_sessions()
        .lock()
        .expect("surge controller session cache poisoned")
        .entry(target_key(target))
        .or_insert_with(|| Arc::new(Mutex::new(None)))
        .clone()
}

pub(super) async fn connect(
    target: &SurgeControllerTarget,
) -> Result<SurgeControllerConnection, MihomoError> {
    let connect_lock = connect_lock(target);
    let _connect = connect_lock.lock().await;
    SurgeControllerConnection::connect(target).await
}

pub(super) fn release_target(target: &SurgeControllerTarget) {
    unary_sessions()
        .lock()
        .expect("surge controller session cache poisoned")
        .remove(&target_key(target));
}

pub async fn with_unary_connection<T, F>(
    target: &SurgeControllerTarget,
    operation: F,
) -> Result<T, MihomoError>
where
    F: for<'a> FnOnce(
        &'a mut SurgeControllerConnection,
    ) -> Pin<Box<dyn Future<Output = Result<T, MihomoError>> + Send + 'a>>,
{
    let slot = unary_slot(target);
    let mut connection = slot.lock().await;
    if connection.is_none() {
        *connection = Some(connect(target).await?);
    }
    let result = operation(
        connection
            .as_mut()
            .expect("unary Surge controller connection initialized"),
    )
    .await;
    if matches!(
        result,
        Err(MihomoError::Network(_) | MihomoError::InvalidJson(_))
    ) {
        *connection = None;
    }
    result
}
