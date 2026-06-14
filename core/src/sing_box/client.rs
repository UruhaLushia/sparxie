use std::collections::HashMap;
use std::sync::{Arc, OnceLock};
use std::time::Duration;

use tokio::sync::Mutex as AsyncMutex;
use tonic::metadata::MetadataValue;
use tonic::service::Interceptor;
use tonic::service::interceptor::InterceptedService;
use tonic::transport::{Channel, ClientTlsConfig, Endpoint};
use tonic::{Request, Status};
use url::Url;

use crate::MihomoError;
use crate::sing_box::proto::daemon::started_service_client::StartedServiceClient;

pub type SingBoxClient = StartedServiceClient<InterceptedService<Channel, AuthInterceptor>>;

#[derive(Clone, Debug)]
pub struct SingBoxTarget {
    pub base_url: String,
    pub secret: Option<String>,
    pub allow_insecure: bool,
}

#[derive(Clone)]
pub struct AuthInterceptor {
    authorization: Option<MetadataValue<tonic::metadata::Ascii>>,
}

impl Interceptor for AuthInterceptor {
    fn call(&mut self, mut request: Request<()>) -> Result<Request<()>, Status> {
        if let Some(value) = &self.authorization {
            request
                .metadata_mut()
                .insert("authorization", value.clone());
        }
        Ok(request)
    }
}

impl SingBoxTarget {
    pub async fn client(&self) -> Result<SingBoxClient, MihomoError> {
        let channel = channel_for(self).await?;
        Ok(StartedServiceClient::with_interceptor(
            channel,
            AuthInterceptor::new(self.secret.as_deref())?,
        ))
    }
}

impl AuthInterceptor {
    fn new(secret: Option<&str>) -> Result<Self, MihomoError> {
        let authorization = secret
            .filter(|s| !s.is_empty())
            .map(|secret| format!("Bearer {secret}").parse())
            .transpose()
            .map_err(|e| MihomoError::Other(format!("sing-box API 密钥无效:{e}")))?;
        Ok(Self { authorization })
    }
}

fn pool() -> &'static AsyncMutex<HashMap<String, Channel>> {
    static POOL: OnceLock<AsyncMutex<HashMap<String, Channel>>> = OnceLock::new();
    POOL.get_or_init(|| AsyncMutex::new(HashMap::new()))
}

async fn channel_for(target: &SingBoxTarget) -> Result<Channel, MihomoError> {
    let key = channel_key(target);
    let mut guard = pool().lock().await;
    if let Some(channel) = guard.get(&key) {
        return Ok(channel.clone());
    }
    let channel = build_channel(target).await?;
    guard.insert(key, channel.clone());
    Ok(channel)
}

async fn build_channel(target: &SingBoxTarget) -> Result<Channel, MihomoError> {
    let (base, https, host) = endpoint_base(target)?;
    let mut endpoint = if https && target.allow_insecure {
        Endpoint::from_shared(base)
            .map_err(|e| MihomoError::InvalidUrl(e.to_string()))?
            .tls_config_with_verifier(
                ClientTlsConfig::new()
                    .domain_name(host)
                    .assume_http2(true)
                    .timeout(Duration::from_secs(5)),
                Arc::new(NoCertVerify),
            )
            .map_err(|e| MihomoError::Network(format!("sing-box TLS: {e}")))?
    } else {
        Endpoint::new(base).map_err(|e| MihomoError::InvalidUrl(e.to_string()))?
    };
    endpoint = endpoint
        .connect_timeout(Duration::from_secs(5))
        .timeout(Duration::from_secs(20));
    endpoint
        .connect()
        .await
        .map_err(|e| MihomoError::Network(format!("sing-box API 连接失败:{e}")))
}

fn endpoint_base(target: &SingBoxTarget) -> Result<(String, bool, String), MihomoError> {
    let parsed =
        Url::parse(target.base_url.trim()).map_err(|e| MihomoError::InvalidUrl(e.to_string()))?;
    let https = match parsed.scheme() {
        "http" => false,
        "https" => true,
        scheme => {
            return Err(MihomoError::InvalidUrl(format!(
                "sing-box API 不支持 {scheme} 地址"
            )));
        }
    };
    let host = parsed
        .host_str()
        .ok_or_else(|| MihomoError::InvalidUrl("缺少主机名".into()))?
        .to_string();
    let port = parsed
        .port_or_known_default()
        .unwrap_or(if https { 443 } else { 80 });
    Ok((
        format!("{}://{}:{port}", parsed.scheme(), host),
        https,
        host,
    ))
}

pub fn target_key(target: &SingBoxTarget) -> String {
    format!(
        "{}|{}|{}",
        target.base_url.trim_end_matches('/'),
        target.secret.as_deref().unwrap_or(""),
        target.allow_insecure
    )
}

fn channel_key(target: &SingBoxTarget) -> String {
    format!(
        "{}|{}",
        target.base_url.trim_end_matches('/'),
        target.allow_insecure
    )
}

#[derive(Debug)]
struct NoCertVerify;

impl rustls::client::danger::ServerCertVerifier for NoCertVerify {
    fn verify_server_cert(
        &self,
        _end_entity: &rustls::pki_types::CertificateDer<'_>,
        _intermediates: &[rustls::pki_types::CertificateDer<'_>],
        _server_name: &rustls::pki_types::ServerName<'_>,
        _ocsp: &[u8],
        _now: rustls::pki_types::UnixTime,
    ) -> Result<rustls::client::danger::ServerCertVerified, rustls::Error> {
        Ok(rustls::client::danger::ServerCertVerified::assertion())
    }

    fn verify_tls12_signature(
        &self,
        _message: &[u8],
        _cert: &rustls::pki_types::CertificateDer<'_>,
        _dss: &rustls::DigitallySignedStruct,
    ) -> Result<rustls::client::danger::HandshakeSignatureValid, rustls::Error> {
        Ok(rustls::client::danger::HandshakeSignatureValid::assertion())
    }

    fn verify_tls13_signature(
        &self,
        _message: &[u8],
        _cert: &rustls::pki_types::CertificateDer<'_>,
        _dss: &rustls::DigitallySignedStruct,
    ) -> Result<rustls::client::danger::HandshakeSignatureValid, rustls::Error> {
        Ok(rustls::client::danger::HandshakeSignatureValid::assertion())
    }

    fn supported_verify_schemes(&self) -> Vec<rustls::SignatureScheme> {
        use rustls::SignatureScheme as S;
        vec![
            S::RSA_PKCS1_SHA256,
            S::RSA_PKCS1_SHA384,
            S::RSA_PKCS1_SHA512,
            S::ECDSA_NISTP256_SHA256,
            S::ECDSA_NISTP384_SHA384,
            S::ED25519,
            S::RSA_PSS_SHA256,
            S::RSA_PSS_SHA384,
            S::RSA_PSS_SHA512,
        ]
    }
}
