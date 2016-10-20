# Dylib exploration

## What is this?
This is a fluent Rust file exploring dynamic system configuration using specs ecs and libloading.

## How does it work?
It uses [Tango](https://github.com/pnkfelix/tango) to explore working with dylibs in a sort-of interactive format.

To see it in action, pull down this crate, and run `cargo test`. That will load these markdown files up, convert them to `.rs` files, and execute the tests. Note: This crate does codegeneration and runtime compilation: you will need a modern (1.13, as of time of writing) rust installation, though if you're running `cargo test`, you're already there!

## First, our dependencies

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

## Next, lets grab what we need

### From libloading
```rust
use libloading::Library;
```

### From specs

## Our supporting modules
### [Dylib codegen](./dylib_codegen.md)
```rust
mod dylib_codegen;
```

## And the rest!

Currently we do nothing. Heres a test block so something shows up on `cargo test`

```rust
#[cfg(test)]
mod tests {
    #[test]
    fn it_works() {
    }
}
```
