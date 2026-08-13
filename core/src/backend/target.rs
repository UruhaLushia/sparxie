#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum BackendType {
    Clash,
    Surge,
    SurgeController,
    SingBox,
}

#[derive(Clone)]
pub struct BackendTarget {
    pub backend_type: BackendType,
    pub base_url: String,
    pub secret: Option<String>,
    pub allow_insecure: bool,
}

impl std::fmt::Debug for BackendTarget {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("BackendTarget")
            .field("backend_type", &self.backend_type)
            .field("base_url", &self.base_url)
            .field("secret", &self.secret.as_ref().map(|_| "<redacted>"))
            .field("allow_insecure", &self.allow_insecure)
            .finish()
    }
}

impl BackendTarget {
    pub(in crate::backend) fn cache_key(&self) -> String {
        let secret = self.secret.as_deref().unwrap_or_default();
        let secret_hash = blake3::hash(secret.as_bytes());
        format!(
            "{:?}|{}|{}|{}",
            self.backend_type,
            self.base_url.trim_end_matches('/'),
            secret_hash.to_hex(),
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

    pub(in crate::backend) fn surge_controller(
        &self,
    ) -> crate::surge_controller::client::SurgeControllerTarget {
        crate::surge_controller::client::SurgeControllerTarget {
            address: self.base_url.clone(),
            password: self.secret.clone(),
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
