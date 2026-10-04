pub mod event;
pub mod migration;
pub mod store;
pub type Result<T> = std::result::Result<T, Box<dyn std::error::Error + Send + Sync>>;
