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

// TODO:
//   Run a login shell (so .profile gets run) and steal its environment vars. It's really hard to inject ENV vars
//   into apps on modern Mac OS, and emacs really needs PATHs and other junk.

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
        // This dedupes environment variables. Mac OS X 10.10 (Yosemite) always gives
        // us 2 PATHs(!!)  See: https://github.com/caldwell/build-emacs/issues/39
        // This iterates through such that the last key wins, which is what we want since
        // the first PATH is always the boring PATH=/usr/bin:/bin:/usr/sbin:/sbin
        let mut env: HashMap<OsString,OsString> = HashMap::new();
        for (k, v) in std::env::vars_os() {
            env.insert(k,v);
        }

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

    osascript(r#"
      tell application "System Events"
        activate
        display dialog "This application will not run on your computer. Sorry!"
      end tell
    "#)
   Ok(())
}

fn osascript(script: &str) -> Result<(), Box<dyn Error>> {
    Command::new("osascript").args(script.lines().filter(|line| !line.trim().is_empty()).map(|line| vec!["-e", line]).flatten().collect::<Vec<&str>>()).status()?;
    Ok(())
}

fn capture(command: &str) -> Result<String, Box<dyn Error>> {
    Ok(String::from_utf8(Command::new("sh").arg("-c").arg(command).output()?.stdout)?)
}
