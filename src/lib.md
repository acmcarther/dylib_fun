# Dylib exploration

## What is this?
This is a fluent Rust file exploring dynamic system configuration using specs ecs and libloading.

## How does it work?
It uses [Tango](https://github.com/pnkfelix/tango) to explore working with dylibs in a sort-of interactive format.

To see it in action, pull down this crate, and run `cargo test`. That will load these markdown files up, convert them to `.rs` files, and execute the tests. Note: This crate does codegeneration and runtime compilation: you will need a modern (1.13, as of time of writing) rust installation, though if you're running `cargo test`, you're already there!

## First, our dependencies
Starting with the stuff we're trying to test

### [Specs](https://github.com/slide-rs/specs)
An entity component system
```rust
extern crate specs;
```

### [libloading](https://github.com/nagisa/rust_libloading)
A library for helping us load rust dylibs
```rust
extern crate libloading;
```

### [libc](https://github.com/rust-lang/libc)
A library that gives us types for handling dangerous pointers
```rust
extern crate libc;
```

And including some helpful libraries for writing our tests

And including some helpful libraries for writing our tests
### [tempdir](https://github.com/rust-lang-nursery/tempdir)
A library to help us generate temporary files and delete them when we're done (for use with codegen)
```rust
extern crate tempdir;
```

## Next, lets grab what we need

### From libloading
```rust
use libloading::Library;
```

### From specs

## Our supporting modules
### [Dylib codegen](./dylib_codegen.md)
This is a module that facilitates generating and working with temporary dylib crates.
```rust
mod dylib_codegen;
```



## Working with TypeId
```rust
#[cfg(test)]
mod typeid_tests {
  use super::dylib_codegen::Crate;
  use super::dylib_codegen::CrateBuilder;
  use std::any::TypeId;
  use libloading::Library;
  use ::libc;

  fn get_type_results(first_source: String, second_source: String) -> (TypeId, TypeId) {
    let mut cb = CrateBuilder::new("typeid_crate".to_owned());
    cb.set_source_code(first_source);
    let krate = cb.build().unwrap();
    let original_typeid = {
      let lib = krate.as_live_dylib();
      let fun = unsafe { lib.get::<fn() -> TypeId>(b"mystruct_typeid").unwrap() };
      fun()
    };

    let new_krate = krate.recompiled_with_source(second_source).unwrap();

    let new_typeid = {
      let new_lib = new_krate.as_live_dylib();
      let new_fun = unsafe { new_lib.get::<fn() -> TypeId>(b"mystruct_typeid").unwrap() };
      new_fun()
    };

    (original_typeid, new_typeid)
  }

  #[test]
  fn unchanged_struct_typeid() {
    let source_code = r#"
      use std::any::TypeId;
      pub struct MyStruct;

      #[no_mangle]
      pub fn mystruct_typeid() -> TypeId {
        TypeId::of::<MyStruct>()
      }
    "#.to_owned();

    let (original, new) = get_type_results(source_code.clone(), source_code);

    assert_eq!(original, new);
  }

  #[test]
  fn new_field_struct_id() {
    let source_code = r#"
      use std::any::TypeId;
      pub struct MyStruct;

      #[no_mangle]
      pub fn mystruct_typeid() -> TypeId {
        TypeId::of::<MyStruct>()
      }
    "#.to_owned();

    let second_source_code = r#"
      use std::any::TypeId;
      pub struct MyStruct {
        f: f32
      }

      #[no_mangle]
      pub fn mystruct_typeid() -> TypeId {
        TypeId::of::<MyStruct>()
      }
    "#.to_owned();


    let (original, new) = get_type_results(source_code, second_source_code);

    assert_eq!(original, new);
  }

  #[test]
  fn new_struct_sanity_check() {
    let source_code = r#"
      use std::any::TypeId;
      pub struct MyStruct;

      #[no_mangle]
      pub fn mystruct_typeid() -> TypeId {
        TypeId::of::<MyStruct>()
      }
    "#.to_owned();

    let second_source_code = r#"
      use std::any::TypeId;
      pub struct OtherStruct;

      #[no_mangle]
      pub fn mystruct_typeid() -> TypeId {
        TypeId::of::<OtherStruct>()
      }
    "#.to_owned();


    let (original, new) = get_type_results(source_code, second_source_code);

    assert!(original != new);
  }

  #[test]
  fn methods_do_not_impact_type_id() {
    let source_code = r#"
      use std::any::TypeId;
      pub struct MyStruct;

      #[no_mangle]
      pub fn mystruct_typeid() -> TypeId {
        TypeId::of::<MyStruct>()
      }
    "#.to_owned();

    let second_source_code = r#"
      use std::any::TypeId;
      pub struct MyStruct;
      impl MyStruct {
        pub fn nothing(&self) {}
      }

      #[no_mangle]
      pub fn mystruct_typeid() -> TypeId {
        TypeId::of::<MyStruct>()
      }
    "#.to_owned();


    let (original, new) = get_type_results(source_code, second_source_code);

    assert_eq!(original, new);
  }
  #[test]
  fn impld_traits_do_not_impact_the_id() {
    let source_code = r#"
      use std::any::TypeId;
      pub struct MyStruct;

      pub trait Frobnicate {}

      #[no_mangle]
      pub fn mystruct_typeid() -> TypeId {
        TypeId::of::<MyStruct>()
      }
    "#.to_owned();

    let second_source_code = r#"
      use std::any::TypeId;
      pub struct MyStruct;

      pub trait Frobnicate {}
      impl Frobnicate for MyStruct {}

      #[no_mangle]
      pub fn mystruct_typeid() -> TypeId {
        TypeId::of::<MyStruct>()
      }
    "#.to_owned();


    let (original, new) = get_type_results(source_code, second_source_code);

    assert_eq!(original, new);
  }

  #[test]
  fn fun_with_opaque_pointers() {
    let first_source = r#"
      extern crate libc;

      #[repr(C)]
      struct Opaque {
        num: i32
      }

      #[no_mangle]
      pub fn gimme_opaque() -> *mut libc::c_void {
        Box::into_raw(Box::new(Opaque {
          num: 11
        })) as *mut libc::c_void
      }
    "#.to_owned();

    let second_source = r#"
      extern crate libc;

      #[repr(C)]
      struct Opaque {
        num: i32
      }

      trait DoTrick {
        fn do_trick(&self) -> i32;
      }

      impl DoTrick for Opaque {
        fn do_trick(&self) -> i32 {
          5 * self.num
        }
      }

      #[no_mangle]
      pub fn handle_opaque(opaque: *mut libc::c_void) -> i32 {
        let opaque: Box<Opaque> = unsafe { Box::from_raw(opaque as *mut Opaque) };

        opaque.do_trick()
      }
    "#.to_owned();
 
    let mut cb = CrateBuilder::new("test_crate".to_owned());
    cb.set_source_code(first_source);
    cb.add_dependency("libc".to_owned(), "0.2.20".to_owned());
    let krate = cb.build().unwrap();
    let opaque: *mut libc::c_void = {
      let lib = krate.as_live_dylib();
      let fun = unsafe { lib.get::<fn() -> *mut libc::c_void>(b"gimme_opaque").unwrap() };
      fun()
    };

    let new_krate = krate.recompiled_with_source(second_source).unwrap();

    let output = {
      let new_lib = new_krate.as_live_dylib();
      let new_fun = unsafe { new_lib.get::<fn(*mut libc::c_void) -> i32>(b"handle_opaque").unwrap() };
      new_fun(opaque)
    };

    assert_eq!(output, 55);
  }
}
```
