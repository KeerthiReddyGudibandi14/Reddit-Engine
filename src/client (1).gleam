import argv
import gleam/bit_array
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/httpc
import gleam/int
import gleam/io
import gleam/json
import gleam/uri

const base_url = "http://localhost:8000"

pub fn main() {
  let argv.Argv(_, _, arguments) = argv.load()

  case arguments {
    ["register", username] -> register_user(username)

    ["create-sr", name, creator_id_str] ->
      create_subreddit(name, creator_id_str)

    ["join-sr", name, user_id_str] -> join_subreddit(name, user_id_str)

    ["leave-sr", name, user_id_str] -> leave_subreddit(name, user_id_str)

    ["post", subreddit_name, author_id_str, body] ->
      create_post(subreddit_name, author_id_str, body)

    ["comment", post_id_str, author_id_str, body] ->
      create_comment(post_id_str, author_id_str, body)

    ["vote-post", post_id_str, voter_id_str, vote_str] ->
      vote_post(post_id_str, voter_id_str, vote_str)

    ["vote-comment", comment_id_str, voter_id_str, vote_str] ->
      vote_comment(comment_id_str, voter_id_str, vote_str)

    ["dm-send", from_id_str, to_id_str, body] ->
      dm_send(from_id_str, to_id_str, body)

    ["dm-reply", thread_id_str, from_id_str, body] ->
      dm_reply(thread_id_str, from_id_str, body)

    ["inbox", user_id_str] -> list_inbox(user_id_str)

    ["thread", thread_id_str] -> list_thread(thread_id_str)

    ["feed", subreddit_name] -> get_feed(subreddit_name)

    _ -> print_usage()
  }
}

fn print_usage() {
  io.println("Usage:")
  io.println("  gleam run -m client -- register alice")
  io.println("  gleam run -m client -- create-sr technology 1")
  io.println("  gleam run -m client -- join-sr technology 1")
  io.println("  gleam run -m client -- post technology 1 \"Hello world\"")
  io.println("  gleam run -m client -- comment 1 1 \"Nice post\"")
  io.println("  gleam run -m client -- vote-post 1 1 1")
  io.println("  gleam run -m client -- dm-send 1 2 \"hey\"")
  io.println("  gleam run -m client -- inbox 1")
  io.println("  gleam run -m client -- thread 10")
}

// Helper to send POST with JSON

fn post_json(url: String, body: json.Json) {
  let body_string = json.to_string(body)
  let assert Ok(uri) = uri.parse(url)
  let assert Ok(base_req) = request.from_uri(uri)
  let req =
    base_req
    |> request.set_method(http.Post)
    |> request.set_body(bit_array.from_string(body_string))
    |> request.set_header("content-type", "application/json")

  httpc.send_bits(req)
  |> print_response
}

fn get(url: String) {
  let assert Ok(uri) = uri.parse(url)
  let assert Ok(base_req) = request.from_uri(uri)
  let req =
    base_req
    |> request.set_method(http.Get)
    |> request.set_body(bit_array.from_string(""))

  httpc.send_bits(req)
  |> print_response
}

fn print_response(
  response: Result(response.Response(BitArray), httpc.HttpError),
) {
  case response {
    Ok(resp) -> {
      io.println("Status: " <> int.to_string(resp.status))
      let body = case bit_array.to_string(resp.body) {
        Ok(text) -> text
        Error(_) -> "<binary body>"
      }
      io.println("Body:")
      io.println(body)
    }

    Error(e) -> io.println("Error: " <> http_error_to_string(e))
  }
}

fn http_error_to_string(e: httpc.HttpError) -> String {
  case e {
    httpc.InvalidUtf8Response -> "invalid_utf8_body"
    httpc.ResponseTimeout -> "response_timeout"
    httpc.FailedToConnect(ip4, ip6) ->
      "failed_to_connect (ipv4: "
      <> inspect_connect_error(ip4)
      <> ", ipv6: "
      <> inspect_connect_error(ip6)
  }
}

fn inspect_connect_error(error: httpc.ConnectError) -> String {
  case error {
    httpc.Posix(code) -> code
    httpc.TlsAlert(code, detail) -> code <> "/" <> detail
  }
}

// CLIENT COMMANDS

// register user
fn register_user(username: String) {
  let url = base_url <> "/api/users/" <> username
  post_json(url, json.object([]))
}

// create subreddit
fn create_subreddit(name: String, creator_id_str: String) {
  let assert Ok(creator_id) = int.parse(creator_id_str)
  let url =
    base_url
    <> "/api/subreddits/"
    <> name
    <> "?creator_id="
    <> int.to_string(creator_id)
  post_json(url, json.object([]))
}

// join subreddit
fn join_subreddit(name: String, user_id_str: String) {
  let assert Ok(user_id) = int.parse(user_id_str)
  let url =
    base_url
    <> "/api/subreddits/"
    <> name
    <> "/join?user_id="
    <> int.to_string(user_id)
  post_json(url, json.object([]))
}

// leave subreddit
fn leave_subreddit(name: String, user_id_str: String) {
  let assert Ok(user_id) = int.parse(user_id_str)
  let url =
    base_url
    <> "/api/subreddits/"
    <> name
    <> "/leave?user_id="
    <> int.to_string(user_id)
  post_json(url, json.object([]))
}

// create post
fn create_post(sub_name: String, author_id_str: String, body: String) {
  let assert Ok(author_id) = int.parse(author_id_str)
  let url = base_url <> "/api/subreddits/" <> sub_name <> "/posts"
  post_json(
    url,
    json.object([
      #("author_id", json.int(author_id)),
      #("body", json.string(body)),
    ]),
  )
}

// comment
fn create_comment(post_id: String, author_id_str: String, body: String) {
  let assert Ok(author_id) = int.parse(author_id_str)
  let url = base_url <> "/api/posts/" <> post_id <> "/comments"

  post_json(
    url,
    json.object([
      #("author_id", json.int(author_id)),
      #("body", json.string(body)),
      #("parent_comment_id", json.null()),
    ]),
  )
}

fn vote_post(post_id: String, voter_id_str: String, vote_str: String) {
  let assert Ok(voter_id) = int.parse(voter_id_str)
  let assert Ok(vote) = int.parse(vote_str)
  let url = base_url <> "/api/posts/" <> post_id <> "/vote"
  post_json(
    url,
    json.object([
      #("voter_id", json.int(voter_id)),
      #("vote", json.int(vote)),
    ]),
  )
}

fn vote_comment(comment_id: String, voter_id_str: String, vote_str: String) {
  let assert Ok(voter_id) = int.parse(voter_id_str)
  let assert Ok(vote) = int.parse(vote_str)
  let url = base_url <> "/api/comments/" <> comment_id <> "/vote"
  post_json(
    url,
    json.object([
      #("voter_id", json.int(voter_id)),
      #("vote", json.int(vote)),
    ]),
  )
}

fn dm_send(from_id_str: String, to_id_str: String, body: String) {
  let assert Ok(from_id) = int.parse(from_id_str)
  let assert Ok(to_id) = int.parse(to_id_str)
  let url = base_url <> "/api/messages"
  post_json(
    url,
    json.object([
      #("from_id", json.int(from_id)),
      #("to_id", json.int(to_id)),
      #("body", json.string(body)),
    ]),
  )
}

fn dm_reply(thread_id: String, from_id_str: String, body: String) {
  let assert Ok(from_id) = int.parse(from_id_str)
  let url = base_url <> "/api/messages/" <> thread_id <> "/reply"
  post_json(
    url,
    json.object([
      #("from_id", json.int(from_id)),
      #("body", json.string(body)),
    ]),
  )
}

fn list_inbox(user_id_str: String) {
  let assert Ok(user_id) = int.parse(user_id_str)
  let url = base_url <> "/api/users/" <> int.to_string(user_id) <> "/inbox"
  get(url)
}

fn list_thread(thread_id: String) {
  let url = base_url <> "/api/messages/" <> thread_id
  get(url)
}

fn get_feed(sub: String) {
  let url = base_url <> "/api/subreddits/" <> sub <> "/posts"
  get(url)
}
