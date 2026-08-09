#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub enum ProxyMemberSort {
    #[default]
    Original,
    Name,
    Delay,
}

#[derive(Clone, Debug, Default)]
pub struct ProxyCatalog {
    pub groups: Vec<ProxyGroupEntry>,
    pub icon_urls: Vec<String>,
}

#[derive(Clone, Debug, Default)]
pub struct ProxyGroupEntry {
    pub name: String,
    pub proxy_type: String,
    pub icon: String,
    pub member_count: u32,
    pub members_hash: u32,
    pub now: String,
    pub now_delay: i32,
    pub test_url: String,
    pub fixed: String,
}

#[derive(Clone, Debug, Default)]
pub struct ProxyMemberEntry {
    pub name: String,
    pub proxy_type: String,
    pub delay: i32,
}

#[derive(Clone, Debug, Default)]
pub struct ProxyMemberSection {
    pub provider: String,
    pub offset: u32,
    pub count: u32,
}

#[derive(Clone, Debug, Default)]
pub struct ProxyMemberWindow {
    pub entries: Vec<ProxyMemberEntry>,
    pub sections: Vec<ProxyMemberSection>,
}
