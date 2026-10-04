use std::{
    io::{self, Read},
    path::PathBuf,
    time::{SystemTime, UNIX_EPOCH},
};
use workbranch_agent_runtime::{Result, event, migration, store};
fn runtime_dir() -> Result<PathBuf> {
    Ok(PathBuf::from(
        std::env::var_os("WORKBRANCH_RUNTIME_DIR").unwrap_or(
            PathBuf::from(std::env::var_os("HOME").ok_or("HOME missing")?)
                .join(".workbranch/runtime")
                .into_os_string(),
        ),
    ))
}
fn now() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}
fn workspace(cwd: &str) -> Option<PathBuf> {
    let cwd = std::fs::canonicalize(cwd).ok()?;
    // Agent cwd must be a registered workbranch workspace or one of its repo descendants.
    for dir in cwd.ancestors() {
        if dir.join(".workbranch.task").is_file() {
            return Some(dir.to_path_buf());
        }
    }
    None
}
fn run(args: &[String]) -> Result<()> {
    let cmd = args.first().map(String::as_str).unwrap_or("help");
    match cmd {
        "version"|"--version"=>println!("workbranch-agent-runtime 0.1.0 (schema 1)"),
        "ingest"=>{
            let provider=args.get(1).ok_or("provider missing")?;
            let mut input=String::new();io::stdin().take(1_048_577).read_to_string(&mut input)?;
            if input.len()>1_048_576{return Err("payload too large".into());}
            let payload:serde_json::Value=serde_json::from_str(&input)?;
            let cwd=payload.get("cwd").and_then(|v|v.as_str()).ok_or("cwd missing")?;
            let Some(root)=workspace(cwd) else {return Ok(());};
            let mut db=store::open(&runtime_dir()?.join("state.sqlite3"))?;
            event::ingest(&mut db,&root.to_string_lossy(),provider,&payload,now())?;
        }
        "register"=>{
            let binary=args.get(1).ok_or("collector path missing")?;
            let binary=PathBuf::from(binary);
            let binary=if binary.is_absolute(){binary}else{std::env::current_dir()?.join(binary)};
            if std::fs::canonicalize(&binary)?!=std::fs::canonicalize(std::env::current_exe()?)? {return Err("collector identity mismatch".into());}
            let dir=runtime_dir()?;
            if dir.is_symlink(){return Err("Runtime directory must not be a symbolic link".into());}
            std::fs::create_dir_all(&dir)?;
            #[cfg(unix)] {
                use std::os::unix::fs::{symlink,PermissionsExt};
                std::fs::set_permissions(&dir,std::fs::Permissions::from_mode(0o700))?;
                let link=dir.join("hook-collector");
                if link.exists()&&!link.is_symlink(){return Err("Refusing to overwrite a non-link hook collector".into());}
                let temporary=dir.join(format!(".hook-collector-{}",std::process::id()));
                symlink(&binary,&temporary)?;
                if let Err(error)=std::fs::rename(&temporary,&link){let _=std::fs::remove_file(&temporary);return Err(error.into());}
            }
            #[cfg(not(unix))] {return Err("Hook registration requires macOS or Linux".into());}
        }
        "snapshot"=>{
            let path=runtime_dir()?.join("state.sqlite3");
            let sessions=if path.exists(){store::snapshot(&store::open_read(&path)?,now())?}else{vec![]};
            println!("{}",serde_json::json!({"schemaVersion":1,"sessions":sessions}));
        }
        "migrate"=>{
            let apply=args.get(1).map(String::as_str)==Some("--apply");
            if !apply && args.get(1).map(String::as_str)!=Some("--dry-run"){return Err("use --dry-run or --apply".into());}
            let _lock = if apply {
                let dir=runtime_dir()?;
                std::fs::create_dir_all(&dir)?;
                let lock_path=dir.join("migration.lock");
                if lock_path.is_symlink(){return Err("Migration lock cannot be a symbolic link".into());}
                let file=std::fs::OpenOptions::new().create(true).truncate(false).read(true).write(true).open(lock_path)?;
                file.try_lock().map_err(|_| "Another migration is running; retry when it finishes")?;
                Some(file)
            } else {None};
            let roots:Vec<PathBuf>=args.iter().skip(2).map(PathBuf::from).collect();
            let report=migration::run(&roots,apply)?;
            println!("{}",serde_json::to_string(&report)?);
            if !report.errors.is_empty(){return Err("migration incomplete; inspect reported errors".into());}
        }
        _=>return Err("usage: workbranch-agent-runtime ingest claude|codex|grok | snapshot | migrate --dry-run|--apply <workspace>...".into())
    }
    Ok(())
}
fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if let Err(e) = run(&args) {
        if args.first().map(String::as_str) == Some("ingest") {
            return;
        }
        eprintln!("{e}");
        std::process::exit(1);
    }
}
