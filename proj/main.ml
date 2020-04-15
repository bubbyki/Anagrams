open Game
open State
open Command

let loopgame game st : unit = failwith "unimpl"

(** [play_game j] starts the game with the letter set generated from the 
    alphabet in file [j]. *)
let play_game j = 
  let json = match Yojson.Basic.from_file j with
    | exception Sys_error s -> failwith ("Your input failed. " 
                                         ^ s ^ "\n Start the game over. ")
    | _ -> Yojson.Basic.from_file j
  in 
  let our_game = combo_set (from_json json) in
  let initst = our_game |> init_state in
  print_endline "Your 6 Letters: "; loopgame our_game initst

(** [main ()] prompts for the game to play, then starts it. *)
let main () = 
  ANSITerminal.(print_string [red]
                  "\n\nWelcome to ANAGRAMS.\n");
  print_endline 
    "Please enter the name of the game alphabet file you want to load.\n";
  (** I think we could also automatically load an alphabet file by random,
      or by number of turns, time limit, etc. *)
  print_string  "> ";
  match read_line () with
  | exception End_of_file -> ()
  | file_name -> play_game file_name

(* Execute the game engine. *)
let () = main ()