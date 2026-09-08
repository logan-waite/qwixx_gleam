import { Result$Ok, Result$Error } from "./gleam.mjs";

export function get_localstorage(key) {
  const value = window.localStorage.getItem(key);

  if (value === null) {
    return Result$Error(undefined);
  }

  try {
    // We'll handle all value parsing (int, string, json, etc) on the gleam side
    return Result$Ok(value);
  } catch (e) {
    return Result$Error(undefined);
  }
}

export function set_localstorage(key, json) {
  window.localStorage.setItem(key, json);
}
