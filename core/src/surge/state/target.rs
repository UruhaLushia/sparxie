use crate::surge::client::{SurgeTarget, target_key as http_target_key};
use crate::surge_controller::client::{SurgeControllerTarget, target_key as controller_target_key};

#[derive(Clone)]
pub(crate) enum Target {
    Http(SurgeTarget),
    Controller(SurgeControllerTarget),
}

impl Target {
    pub(crate) fn key(&self) -> String {
        match self {
            Self::Http(target) => format!("http|{}", http_target_key(target)),
            Self::Controller(target) => {
                format!("controller|{}", controller_target_key(target))
            }
        }
    }

    pub(crate) fn is_http(&self) -> bool {
        matches!(self, Self::Http(_))
    }
}

impl From<SurgeTarget> for Target {
    fn from(target: SurgeTarget) -> Self {
        Self::Http(target)
    }
}

impl From<SurgeControllerTarget> for Target {
    fn from(target: SurgeControllerTarget) -> Self {
        Self::Controller(target)
    }
}
