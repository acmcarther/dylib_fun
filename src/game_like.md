```rust
#[cfg(test)]
mod game_like_tests {
  use ::dylib_codegen::Crate;
  use ::dylib_codegen::CrateBuilder;
  use ::libc;

  static GAME_PRELUDE: &'static str = r#"
    extern crate libc;
    #[macro_use]
    extern crate lazy_static;

    pub use ffi::*;
    use std::sync::Mutex;
  "#;

  static GAME_BOILERPLATE: &'static str = r#"
    trait Game {
      fn load(&mut self, state: *mut libc::c_void);
      fn run(&mut self);
      fn stop(&mut self) -> *mut libc::c_void;
    }

    lazy_static! {
      static ref GAME_IMPL: Mutex<GameImpl> = Mutex::new(GameImpl::new());
    }

    mod ffi {
      use super::Game;
      use ::libc;
      use super::GAME_IMPL;

      #[no_mangle]
      pub fn load(state: *mut libc::c_void) {
        unsafe { GAME_IMPL.lock().unwrap().load(state) }
      }

      #[no_mangle]
      pub fn run() {
        unsafe { GAME_IMPL.lock().unwrap().run() }
      }

      #[no_mangle]
      pub fn stop() -> *mut libc::c_void {
        unsafe { GAME_IMPL.lock().unwrap().stop() }
      }
    }
  "#;

  fn build_source(game_src: &str) -> String {
    format!("{}\n{}\n{}",
      GAME_PRELUDE,
      game_src,
      GAME_BOILERPLATE)
  }

  #[test]
  fn basic_test() {
    let basic_game = r#"
      type FakeState = u32;
      struct BasicGame {}
      type GameImpl = BasicGame;

      impl BasicGame {
        pub fn new() -> BasicGame{
          BasicGame {}
        }
      }

      impl Game for BasicGame {
        fn load(&mut self, state: *mut libc::c_void) {
          // Need to at least dealloc the passed pointer or it'll leak
          unsafe { Box::from_raw(state as *mut FakeState) };
        }

        fn run(&mut self) {
          // Do nothing
        }

        fn stop(&mut self) -> *mut libc::c_void {
          // Yield a fake state
          Box::into_raw(Box::new(52)) as *mut libc::c_void
        }
      }
    "#;

    let full_source = build_source(basic_game);

    let mut cb = CrateBuilder::new("test_game".to_owned());
    cb.set_source_code(full_source);
    cb.add_dependency("libc".to_owned(), "0.2.17".to_owned());
    cb.add_dependency("lazy_static".to_owned(), "0.2.2".to_owned());
    let krate = cb.build().unwrap();

    // Run and keep the state
    let opaque_state: *mut libc::c_void = {
      let lib = krate.as_live_dylib();
      let run = unsafe { lib.get::<fn()>(b"run").unwrap() };
      let stop = unsafe { lib.get::<fn() -> *mut libc::c_void>(b"stop").unwrap() };

      run();
      run();
      stop()
    };

    let final_result = {
      // Reload
      let lib = krate.as_live_dylib();
      let load = unsafe { lib.get::<fn(*mut libc::c_void)>(b"load").unwrap() };
      let run = unsafe { lib.get::<fn()>(b"run").unwrap() };
      let stop = unsafe { lib.get::<fn() -> *mut libc::c_void>(b"stop").unwrap() };
      load(opaque_state);
      run();
      run();
      stop() // toss the state
    };

    let boxed_result = unsafe { Box::from_raw(final_result as *mut u32) };
    assert_eq!(boxed_result, Box::new(52));
  }
}
```
