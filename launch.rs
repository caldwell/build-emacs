// Copyright © 2012-2022 David Caldwell <david@porkrind.org>
//
// This launcher code is from emacsformacosx.com and is not part of Emacs
// proper. It exists so that there can be a single download that contains
// binaries for all supported Mac OS X versions.
//
// Why not just use a fat binary? Because fat binaries can only hold 1 of
// each architecture and Emacs has multiple x86_64 architectures binaries.
//
// Why are there multiple x86_64 binaries? Because the Emacs source used to
// do OS feature detection at compile time instead of at run-time. So if you
// build Emacs on 10.9 then it would contain hard-coded calls to 10.9 APIs
// and would not run on 10.6. If you compiled it on 10.6, then it would also
// run on 10.9, but it wouldn't take advantage of any of the features in
// 10.9. This has since changed, so this launcher could probably be
// eliminated with some work.
//
// Bug reports for this launcher should go here:
//   https://github.com/caldwell/build-emacs
//
// License:
//
//   This program is free software: you can redistribute it and/or modify
//   it under the terms of the GNU General Public License as published by
//   the Free Software Foundation, either version 3 of the License, or
//   (at your option) any later version.
//
//   This program is distributed in the hope that it will be useful,
//   but WITHOUT ANY WARRANTY; without even the implied warranty of
//   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//   GNU General Public License for more details.
//
//   You should have received a copy of the GNU General Public License
//   along with this program.  If not, see <http://www.gnu.org/licenses/>.

#![feature(exit_status_error)]

use std::error::Error;
use std::vec::Vec;
use std::collections::hash_map::HashMap;
use std::process::Command;
use std::path::{Path,PathBuf};
use std::ffi::{OsString};
use std::os::unix::process::CommandExt; // for .exec()

use version_compare::{Cmp, Version};
use glob::glob;
use regex::Regex;

fn main() {
    possibly_dump_environment();
    if let Err(e) = launch() {
        show_dialog("Emacs failed to launch!", &e.to_string())
    }
}

fn launch() -> Result<(), Box<dyn Error>> {
    let version_str = capture("sw_vers -productVersion")?;
    let version = Version::from(&version_str.trim()).ok_or(format!("Couldn't parse version: '{}'", version_str))?;
    let arch = capture("uname -m")?.trim().to_owned();

    // For some reason the "Open using Rosetta" option gets set on arm machines. This causes `uname` to report
    // x86_64 and the x86_64 binary crashes under Rosetta for reasons I don't understand. This confuses people
    // so lets just undercut the Finder checkbox and run the proper native exe.
    let rosetta = capture("sysctl -in sysctl.proc_translated")?.trim() == "1";
    let arch = if arch == "x86_64" && rosetta { "arm64".to_owned() } else { arch };

    // Support direct symlinks to Emacs.app/Contents/MacOS/Emacs
    let mut exe = std::env::current_exe()?;
    //while exe.as_path().is_symlink() { exe = std::fs::read_link(exe)? } // is_symlink() is unstable :-(
    while std::fs::symlink_metadata(&exe)?.file_type().is_symlink() { exe = std::fs::read_link(exe)? }

    #[derive(Clone,Debug)]
    struct Variant {
        exe: PathBuf,
        arch: String,
        version: String,
        id: String,
    }

    let file_re = Regex::new(r"^.*-(.+)-([\d._]+)$").unwrap();
    let candidates: Vec<Variant> = glob(&exe.parent().unwrap_or(Path::new(".")).join("Emacs-*").into_os_string().to_string_lossy())?
        .filter(|p| p.is_ok()).map(|p| p.unwrap())
        .map(|file| {
            file_re.captures(&file.to_string_lossy())
                .map(|c| { Variant{
                               exe: file.clone(),
                               arch: c[1].to_owned(),
                               version: c[2].replace("_",".").to_owned(),  // see the 'combine-and-package' script in the build-emacs repo
                               id: format!("{}-{}", &c[1], &c[2]),
                }})
        })
        .filter(|v| v.is_some()).map(|v| v.unwrap())
        .collect();
    let mut compat: Vec<&Variant> = candidates.iter().filter(|v| v.arch == arch && version_compare::compare(&v.version, &version_str) != Ok(Cmp::Gt)).collect();
    compat.sort_by(|a,b| version_compare::compare(&b.version, &a.version).unwrap_or(Cmp::Eq).ord().unwrap());
    let emacs = compat.iter().nth(0);

    if let Some(emacs) = emacs {
        let mut env = if unsafe { getppid() } == 1 { // Our parent process id is 1 when we get launched from Finder (or the Dock, or some other OS way).
            get_shell_environment().or_else::<(),_>(|e| { eprintln!("get_shell_environment failed: {}", e); Ok(dedup_environment()) }).unwrap()
        } else {
            dedup_environment() // Probably launched from Terminal, inherit env vars in this case.
        };

        // Emacs.app sticks Emacs.app/Contents/MacOS/{bin,libexec} on the end of the PATH when it starts, so if we
        // stick our own architecture dependent paths on the end of the PATH then they will override Emacs's paths
        // while not affecting any user paths.
        let base_dir = exe.parent().unwrap_or(Path::new(".")).canonicalize()?;
        env.insert(OsString::from("PATH"), OsString::from(format!("{}:{}:{}",
                                                                  &env.get(&OsString::from("PATH")).map(|p|p.to_string_lossy()).unwrap_or(std::borrow::Cow::Borrowed("")),
                                                                  base_dir.join(format!("bin-{}", emacs.id)).to_string_lossy(),
                                                                  base_dir.join(format!("libexec-{}", emacs.id)).to_string_lossy())));

        // Launch! Looks like it always errors because when exec() is successful it never returns
        Err(Command::new(emacs.exe.clone())
            .args(std::env::args_os().skip(1))
            .env_clear()
            .envs(env)
            .exec())?
    }

    show_dialog("This application will not run on your computer. Sorry!",
                &format!("The Emacs Launcher detected OS version {} on {} architecture.\n\nThe detected Emacs binaries are:\n{}",
                         version, arch,
                         match candidates.iter().map(|v| format!("• arch {}, min OS {}\n", v.arch, v.version)).collect::<Vec<String>>().join("") {
                             s if s == "" => String::from("None. :-("),
                             s => s,
                         }
                ));
   Ok(())
}


fn capture(command: &str) -> Result<String, Box<dyn Error>> {
    Ok(String::from_utf8(Command::new("sh").arg("-c").arg(command).output()?.stdout)?)
}

const DUMP_ENV_NAME: &str = "EMACS_LAUNCHER_PLEASE_DUMP_YOUR_ENV";
use serde_json;
use std::os::unix::io::FromRawFd;

fn possibly_dump_environment() {
   if let Some(fd_s) = std::env::var_os(&DUMP_ENV_NAME) {
        let fd = fd_s.to_string_lossy().parse::<i32>().unwrap_or(1);
        let writer = unsafe { std::fs::File::from_raw_fd(fd) };
        let mut env = vec![];
        for (k, v) in std::env::vars_os() {
            if k != DUMP_ENV_NAME {
                env.push([k,v]);
            }
        }
        serde_json::to_writer(writer, &env);

        std::process::exit(0);
    }
}

fn pipe() -> Result<(std::fs::File, std::fs::File), std::io::Error> {
    let mut fds: [libc::c_int; 2] = [0,0];
    let res = unsafe { libc::pipe(fds.as_mut_ptr()) };
    if res != 0 {
        return Err(std::io::Error::last_os_error());
    }
    unsafe { Ok((std::fs::File::from_raw_fd(fds[0]),
                 std::fs::File::from_raw_fd(fds[1]))) }
}

fn get_shell_environment() -> Result<HashMap<OsString,OsString>, Box<dyn Error>> {
    use std::os::unix::io::AsRawFd;
    use std::io::Read;
 
    fn osstr(s: &str) -> OsString { OsString::from(s) }
    let (mut reader, writer) = pipe()?;
    let mut child = Command::new(std::env::var_os("SHELL").unwrap_or(osstr("sh"))).args([osstr("--login"), osstr("-c"), std::env::current_exe()?.into_os_string()])
                                    .env(DUMP_ENV_NAME, format!("{}", writer.as_raw_fd()))
                                    .stdin(std::process::Stdio::null())
                                    .spawn()?;
    drop(writer); // force parent to close writer
    let mut env_raw = Vec::new();
    let r2end = reader.read_to_end(&mut env_raw);
    let status = child.wait()?; // Make sure we call wait
    status.exit_ok()?;
    let _count = r2end?;

    // This dedupes environment variables as a side effect (see comment in dedup_environment())
    let mut env: HashMap<OsString,OsString> = HashMap::new();
    for e in serde_json::from_slice::<Vec<[OsString;2]>>(&env_raw)? {
        env.insert(e[0].clone(), e[1].clone());
    }

    Ok(env)
}

fn dedup_environment() -> HashMap<OsString,OsString> {
    // This dedupes environment variables. Mac OS X 10.10
    // (Yosemite) always gives us 2 PATHs(!!)  See:
    // https://github.com/caldwell/build-emacs/issues/39 This iterates
    // through such that the last key wins, which is what we want since the
    // first PATH is always the boring PATH=/usr/bin:/bin:/usr/sbin:/sbin
    let mut env: HashMap<OsString,OsString> = HashMap::new();
    for (k, v) in std::env::vars_os() {
        env.insert(k,v);
    }
    env
}

extern crate cocoa;
#[macro_use] extern crate objc;

use cocoa::base::{id, nil};
use cocoa::foundation::{NSAutoreleasePool, NSString, NSInteger};
use cocoa::appkit::*;

fn show_dialog(message: &str, info: &str) {
    unsafe {
        let _pool = NSAutoreleasePool::new(nil);
        let app = NSApp();
        app.setActivationPolicy_(NSApplicationActivationPolicyRegular);
        let alert = NSAlert::alloc(nil).init().autorelease();
        alert.setMessageText_(ns_string(message));
        alert.setInformativeText_(ns_string(info));
        alert.addButtonWithTitle_(ns_string("Quit"));
        alert.runModal();
    }
}

fn ns_string(s: &str) -> id {
    unsafe { NSString::alloc(nil).init_str(s) }
}

// This should probably be part of the cocoa crate:
#[allow(non_snake_case)]
trait NSAlert: Sized {
    unsafe fn alloc(_: Self) -> id {
        msg_send![class!(NSAlert), alloc]
    }
    unsafe fn setInformativeText_(self, text: id/*NSString*/) -> id;
    unsafe fn setMessageText_(self, text: id/*NSString*/) -> id;
    unsafe fn addButtonWithTitle_(self, title: id/*NSString*/) -> id;
    unsafe fn runModal(self) -> NSInteger;
}

impl NSAlert for id {
    unsafe fn setInformativeText_(self, text: id/*NSString*/) -> id {
        msg_send![self, setInformativeText: text]
    }
    unsafe fn setMessageText_(self, text: id/*NSString*/) -> id {
        msg_send![self, setMessageText: text]
    }
    unsafe fn addButtonWithTitle_(self, title: id/*NSString*/) -> id /* (NSButton *) */ {
        msg_send![self, addButtonWithTitle: title]
    }
    unsafe fn runModal(self) -> NSInteger {
        msg_send![self, runModal]
    }
}

// This is in the libc crate, but it seems silly to pull in a whole crate for one line:
extern "C" {
    pub fn getppid() -> i32;
}
