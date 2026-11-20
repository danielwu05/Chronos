//! Root-side anti-cheat vault (installed by the guard as /usr/local/lib/chronos/chronos_vault).
//!   chronos_vault sync --user U --db PATH      mirror/restore (guard loop, every 5 s)
//!   chronos_vault unlock --user U --db PATH    challenge text on stdin
//!   chronos_vault status --user U
//!   chronos_vault uninstall --user U

use rust_lib_chronos_app::vault;
use std::io::Read;
use std::path::PathBuf;

fn arg(args: &[String], name: &str) -> Option<String> {
    args.iter().position(|a| a == name).and_then(|i| args.get(i + 1)).cloned()
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let cmd = args.get(1).map(String::as_str).unwrap_or("");
    let Some(user) = arg(&args, "--user").filter(|u| !u.is_empty() && !u.contains('/')) else {
        eprintln!("chronos_vault: --user obrigatório");
        std::process::exit(2);
    };
    let db = arg(&args, "--db").map(PathBuf::from);
    let code = match cmd {
        "sync" => match db {
            Some(db) => match vault::sync(&user, &db) {
                Ok(r) => {
                    for (k, d) in &r.events {
                        println!("{k}: {d}");
                    }
                    0
                }
                Err(e) => {
                    eprintln!("chronos_vault: {e}");
                    1
                }
            },
            None => 2,
        },
        "unlock" => {
            let mut text = String::new();
            let _ = std::io::stdin().read_to_string(&mut text);
            match db {
                Some(db) => match vault::unlock(&user, &db, &text) {
                    Ok(()) => 0,
                    Err(e) => {
                        eprintln!("{e}");
                        1
                    }
                },
                None => 2,
            }
        }
        "status" => {
            let (active, parental) = vault::status(&user);
            println!("anti_cheat_active={}", active as u8);
            println!("parental={}", parental as u8);
            0
        }
        "uninstall" => match vault::uninstall(&user) {
            Ok(()) => 0,
            Err(e) => {
                eprintln!("{e}");
                1
            }
        },
        _ => {
            eprintln!("uso: chronos_vault {{sync|unlock|status|uninstall}} --user U [--db PATH]");
            2
        }
    };
    std::process::exit(code);
}
