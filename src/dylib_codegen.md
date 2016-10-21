# Dylib Codegen

## What is this
This is a module to generate dylib systems and components (into tmp), cmpile them, and try to link them.

It should be great fun!

## First, lets grab what we need
```rust
use std::fs;
use std::fs::File;
use std::io::Write;
use tempdir::TempDir;
use std::path::Path;
use std::io;
use std::path::PathBuf;
use std::collections::HashMap;
use std::process::Command;
use libloading::Library;
```
## Overview of the problem

So what we'd like to be able to do is generate entire crates that we can build and link as dynamic libraries.

## Implementation

We'll need some core abstractions:
- Some kind of crate type
- Maybe a kind of "crate builder" type

Lets start with the crate.

What should our crate type have? Maybe a directory, and a crate name, to start with.

```rust
pub struct Crate {
  directory: TempDir,
  name: String
}
```

Is that enough to get us going? I think so!

What will our user need to be able to do with the crate? They'll probably want to get a dynamic library out of it, so lets let them do that

```rust
impl Crate {
```
  First, the dylib-yielding method itself:

  We're going to employ `libloading` here, with the path provided, to open that new crate up! We're also going to hand wave the crate-path to dylib path part for now, as `lib_path`.
```rust
  pub fn as_live_dylib(&self) -> Library {
    Library::new(self.lib_path()).unwrap()
  }
```
  And lets define `lib_path` helper method. Its going to need to join our crate path to the relative path leading to the dylib.

  I happen to know the exact location of our generated dylib (or rather, I do after guessing and checking.
```rust
  pub fn lib_path(&self) -> PathBuf {
    let underscored_path = self.name.replace('-', "_");
    let dylib_name = format!("lib{}.so", underscored_path);
    self.directory.path().join("target/debug").join(dylib_name)
  }
```

  We'll probably also want to be able to recompile the crate with a new source, so lets add that. We're going to leverage some helper functionss that we'll write later for the `CrateBuilder`
```rust
  pub fn recompiled_with_source(self, new_source: String) -> Result<Crate, BuildErr> {
    write_lib_rs(&self.directory, new_source)
      .and_then(|_| compile_crate(&self.directory))
      .map(|_| self)
  }
}
```

And thats all there is to our struct!

Take special notice that we're not providing any sort of `new` method. We're leaving that work to our `CrateBuilder` type.

Lets now talk about how we're going to build a crate.

A crate needs two things: a `Cargo.toml`, and some source code. For our purposes, lets only support having a single `lib.rs` source file.

What features do we need to support?

Well, it would be nice to support specifying the crate's name, the crates dependencies, and the lib.rs file. That sounds like what our `CrateBuilder` will need to build us a complete crate, so lets do it!

```rust
pub struct CrateBuilder {
  crate_name: String,
  dependencies: HashMap<Dependency, Version>,
  source_code: String
}
```

And we'll define what a `Dependency` and a `Version` are. For now, I'm terribly lazy, so lets just alias them to `String`

```rust
pub type Dependency = String;
pub type Version = String;
```

We actually know that a dependency crate name and a version have certain constraints, but we'll not bother too much with the error checking -- it should be obvious in our limited context if we've botched one or the other.

However, since we've singled them out now, if we chose to make them more complex later, we could do that with minimal invasiveness.

Now how exactly will a user interact with our `CrateBuilder` to get a `Crate` thats ready for them to use?

Well, we'll want to have them provide the three values we require, and then give them some sort of `build` method that literally compiles the crate. We're really employing the "builder" pattern here.

So, starting off with the CrateBuilder implementation:

```rust
impl CrateBuilder {
```
  First lets have them create their CrateBuilder. Whats essential here is the `crate_name`, so lets have them provide that first.
```rust
  pub fn new(crate_name: String) -> CrateBuilder {
    CrateBuilder {
      crate_name: crate_name,
      dependencies: HashMap::new(),
      source_code: String::new()
    }
  }
```
  One really cool feature of our current crate builder is that, if a user so chose, they could build it immediately! This configuration is a totally valid (if boring) crate.

  Now, lets let them add a dependency. Super easy!
```rust
  pub fn add_dependency(&mut self, n: Dependency, v: Version) {
    self.dependencies.insert(n, v);
  }
```

  And lets give them a way to drop in their source code
```rust
  pub fn set_source_code(&mut self, s: String) {
   self.source_code = s;
  }
```
  And, for the grand finale, lets let them build their crate. This is a big job, so we'll employ some helper functions.

```rust
  pub fn build(self) -> Result<Crate, BuildErr> {
    let dir = try!(generate_directory(&self.crate_name));
    try!(generate_toml(&dir, &self.crate_name, self.dependencies));
    try!(generate_lib_rs(&dir, self.source_code));
    try!(compile_crate(&dir));

    Ok(Crate {
      name: self.crate_name,
      directory: dir
    })
  }
}
```
  And, here comes the dirty work.

```rust
fn generate_directory(crate_name: &str) -> Result<TempDir, BuildErr> {
  TempDir::new(crate_name).map_err(BuildErr::DirErr)
}

fn generate_toml(directory: &TempDir, crate_name: &String, dependencies: HashMap<Dependency, Version>) -> Result<(), BuildErr> {
  let deps: String = dependencies.iter()
    .map(|(k, v)| format!("\"{}\" = \"{}\"\n", k, v))
    .collect();
  File::create(directory.path().join("Cargo.toml"))
    .and_then(|mut f| f.write_all(format!("
      [package]
      name = \"{}\"
      version = \"0.0.1\"

      [dependencies]
      {}

      [lib]
      crate-type = [\"cdylib\"]
    ", crate_name, deps).as_bytes()))
    .map_err(BuildErr::TomlErr)
}

fn generate_lib_rs(directory: &TempDir, source_code: String) -> Result<(), BuildErr> {
  fs::create_dir(directory.path().join("src/"))
    .map_err(BuildErr::SrcErr)
    .and_then(|_| write_lib_rs(directory, source_code))
}

fn write_lib_rs(directory: &TempDir, source_code: String) -> Result<(), BuildErr> {
  File::create(directory.path().join("src/lib.rs"))
    .and_then(|mut f| f.write_all(source_code.as_bytes()))
    .map_err(BuildErr::SrcErr)
}


fn compile_crate(directory: &TempDir) -> Result<(), BuildErr> {
  Command::new("cargo")
    .arg("build")
    .current_dir(directory)
    .output()
    .map(|_| ())
    .map_err(BuildErr::CompileErr)
}
```

We used that fancy `BuildErr` type up above, lets quickly enumerate it

```rust
#[derive(Debug)]
pub enum BuildErr {
 DirErr(io::Error),
 TomlErr(io::Error),
 SrcErr(io::Error),
 CompileErr(io::Error)
}
```

And, now lets test

```rust
#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn can_create_trivial_crate() {
    let cb = CrateBuilder::new("test_crate".to_owned());
    cb.build().unwrap();
  }

  #[test]
  fn can_link_trivial_crate() {
    let cb = CrateBuilder::new("test_crate".to_owned());
    let krate = cb.build().unwrap();
    krate.as_live_dylib();
  }

  #[test]
  fn can_link_a_real_function() {
    let mut cb = CrateBuilder::new("test_crate_w_function".to_owned());
    cb.set_source_code(r#"
      #[no_mangle]
      pub fn return_three() -> i32 { 3 }
    "#.to_owned());
    let krate = cb.build().unwrap();
    let lib = krate.as_live_dylib();
    let fun = unsafe { lib.get::<fn() -> i32>(b"return_three").unwrap() };
    assert_eq!(fun(), 3);
  }

  #[test]
  fn can_trivially_add_dependencies() {
    let mut cb = CrateBuilder::new("test_crate_w_dep".to_owned());
    cb.add_dependency("log".to_owned(), "0.3.6".to_owned());
    cb.set_source_code("extern crate log;".to_owned());
    let krate = cb.build().unwrap();
    krate.as_live_dylib();
  }

  #[test]
  fn can_rebuild_crate_with_new_source() {
    let mut cb = CrateBuilder::new("test_crate_w_function".to_owned());
    cb.set_source_code(r#"
      #[no_mangle]
      pub fn return_something() -> i32 { 3 }
    "#.to_owned());
    let krate = cb.build().unwrap();
    {
      let lib = krate.as_live_dylib();
      let fun = unsafe { lib.get::<fn() -> i32>(b"return_something").unwrap() };
      assert_eq!(fun(), 3);
    }

    let rekrate = krate.recompiled_with_source(r#"
      #[no_mangle]
      pub fn return_something() -> i32 { 4 }
    "#.to_owned()).unwrap();
    {
      let lib = rekrate.as_live_dylib();
      let fun = unsafe { lib.get::<fn() -> i32>(b"return_something").unwrap() };
      assert_eq!(fun(), 4);
    }
  }
}
```
