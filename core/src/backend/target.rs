#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum BackendType {
    Clash,
    Surge,
    SingBox,
}

#[derive(Clone, Debug)]
pub struct BackendTarget {
    pub backend_type: BackendType,
    pub base_url: String,
    pub secret: Option<String>,
    pub allow_insecure: bool,
}

impl BackendTarget {
    pub(in crate::backend) fn cache_key(&self) -> String {
        format!(
            "{:?}|{}|{}|{}",
            self.backend_type,
            self.base_url.trim_end_matches('/'),
            self.secret.as_deref().unwrap_or(""),
            self.allow_insecure,
        )
    }

    pub(in crate::backend) fn clash(&self) -> crate::clash::api::MihomoTarget {
        crate::clash::api::MihomoTarget {
            base_url: self.base_url.clone(),
            secret: self.secret.clone(),
            allow_insecure: self.allow_insecure,
        }
    }

    pub(in crate::backend) fn surge(&self) -> crate::surge::client::SurgeTarget {
        crate::surge::client::SurgeTarget {
            base_url: self.base_url.clone(),
            key: self.secret.clone(),
            allow_insecure: self.allow_insecure,
        }
    }

    pub(in crate::backend) fn sing_box(&self) -> crate::sing_box::client::SingBoxTarget {
        crate::sing_box::client::SingBoxTarget {
            base_url: self.base_url.clone(),
            secret: self.secret.clone(),
            allow_insecure: self.allow_insecure,
        }
    }
}
