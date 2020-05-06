open Game
open Command
open State

(** [print winners text] prints the winners. *)
let rec print winners text = 
  print_endline text;
  if (text = "") && (List.length winners = 2)
  then (List.nth winners 0 |> string_of_int) ^ " and " 
       ^ (List.nth winners 1 |> string_of_int)
  else 
    match winners with 
    | [] -> text 
    | id::[] -> print [] (text ^ "and " ^ (id |> string_of_int))
    | id::t -> print t (text ^ (id |> string_of_int) ^ ", ")

(** [end_phase game st] prints the winning message and exits the game. *)
let rec end_phase game st = 
  let winner_check = winner_check st in 
  match winner_check with 
  | (winners,points) ->
    let p_text = points |> string_of_int in 
    if List.length winners > 1 
    then let w_text = print (List.rev winners) "" in 
      ANSITerminal.(print_string [red] ("Players " ^ w_text ^ 
                                        " have tied with " ^ p_text ^ 
                                        " points! Congratulations!\n")); exit 0
    else let w_text = List.hd winners |> string_of_int in 
      ANSITerminal.(print_string [red] ("Player " ^ w_text ^ 
                                        " has won the game with " ^ p_text 
                                        ^ " points! Congratulations!\n")); 
      exit 0 


(** [check_phase game st] is the check phase of [game] with the final state 
    [st], where players check each other's word lists. *)
let rec check_phase game st = 
  print_endline 
    "If everything looks good, enter 'valid', or if any words look wrong, 
      enter 'invalid (the word or words separated with space)'. "; 
  if current_player st > State.player_count st 
  then (ignore(Sys.command "clear"); end_phase game st)
  else (
    print_endline ("(Player " ^ (State.current_player st |> string_of_int)
                   ^ ") " ^ "Check your next player's word list:");
    State.print_player_word_list st (next_player st);
    print_string "> ";
    (match parse_check (read_line()) with
     | exception Empty -> print_endline "Please enter a command."; 
       check_phase game st
     | exception Malformed -> 
       print_endline
         "Malformed command. Available commands: 'valid', 'invalid'"; 
       check_phase game st
     | your_command -> (match your_command with
         | Valid -> State.valid game st |> check_phase game
         | Invalid wl -> State.invalid wl game st |> check_phase game))
  )

(** [each_turn_print st game] prints the pool, all players' wordlists, and the 
    current player's letter for each turn in pool mode. *)
let each_turn_print st game rep = 
  if not rep then begin
    (* First, we want to print out the pool: *)
    print_list game 2 rep;
    (* Print all player's current words. *)
    print_all_player_word_list st;
    (* Print each player's letter. *)
    print_player_letter st end
  else ()

let game_info st rep mode = 
  if rep then ()
  else
    let turns_left = State.turns st in 
    let points = State.current_player_points st |> string_of_int in 
    print_endline ("There are " ^ (turns_left |> string_of_int) 
                   ^ " turns left in the game.");
    print_endline ("(Player " ^ (State.current_player st |> string_of_int)
                   ^ "), you currently have " ^ points 
                   ^ " points. Enter your word: ");
    let () = (if mode = "pool" 
              then (ANSITerminal.(print_string [yellow] 
                                    ("Available commands: 'create [word]', 
                    'pass',
                    'steal [player_id] [stolen_word] [new_word]',  
                    'quit'.\n"));)
              else 
                ANSITerminal.(print_string [yellow] 
                                ("Available commands: 'create [word]', 
                    'pass',
                    'swap [letter]',  
                    'quit'.\n"));) in begin
      if not (current_player_stolen st = []) then start_message st else () end



(** [loopgame2 game st json rep] is the [game] with updating states [st] in pool 
    mode.*)
let rec loopgame2 game st json rep: unit =  
  let turns_left = State.turns st in 
  if turns_left = 0 
  then (
    ignore(Sys.command "clear");
    ANSITerminal.(print_string [green] 
                    "Turns completed! Entering check phase... \n \n"); 
    check_phase game st)
  else (
    each_turn_print st (get_pool st) rep;
    game_info st rep "pool";
    print_string "> ";
    match parse (read_line()) with
    | exception Empty -> ANSITerminal.(print_string [red] 
                                         "Please enter a command.\n"); 
      loopgame2 game st json true
    | exception Malformed -> 
      ANSITerminal.(print_string [red] 
                      "Malformed command. Please use available commands.\n"); 
      loopgame2 game st json true
    | your_command ->  (match your_command with
        | Quit -> print_endline "Bye!"; exit 0
        | Pass -> 
          ignore(Sys.command "clear");
          print_endline ("Player " ^ (State.current_player st |> string_of_int) 
                         ^ " has passed.\n \n"); 
          begin match pass st with 
            | Legal st' -> loopgame2 (get_pool st') st' json false
            | Illegal s -> failwith "Impossible error"
          end
        | Create w -> 
          if List.mem_assoc (String.uppercase_ascii w) 
              (State.current_player_wordlist st) 
          then (ANSITerminal.(print_string [red]  
                                "This word has already been created.\n"); 
                loopgame2 game st json) true
          else 
            begin match create w st false with
              | Illegal s-> 
                (ANSITerminal.(print_string [red] s)); 
                loopgame2 (get_pool st) st json true
              | Legal st' -> ignore(Unix.sleep 2);ignore(Sys.command "clear"); 
                loopgame2 (get_pool st') st' json false
            end
        | Steal (id, old_word, new_word) -> begin
            match steal old_word new_word id st with 
            | Illegal s-> print_endline s; 
              loopgame2 game st json true;
            | Legal st' ->  
              begin match create new_word st' true with 
                | Illegal s -> (ANSITerminal.(print_string [red] s));
                  loopgame2 game st json true
                | Legal st' -> ignore(Unix.sleep 2);ignore(Sys.command "clear");
                  loopgame2 (get_pool st') st' json false end
          end
        |_ ->  ANSITerminal.(print_string [red] "Malformed command. 
        Please use available commands.\n"; 
                             loopgame2 game st json true)
      )

  )

(** [loopgame game st json] is the [game] with updating states [st] in normal
    mode. *)
let rec loopgame game st json rep: unit = 
  let turns_left = State.turns st in 
  if turns_left = 0 
  then (
    ignore(Sys.command "clear");
    ANSITerminal.(print_string [green] 
                    "Turns completed! Entering check phase... \n \n"); 
    check_phase game st)
  else (
    let set = State.current_player_letter_set st in 
    print_list (set) 1 rep;
    game_info st rep "normal";
    print_string "> ";
    match parse (read_line()) with
    | exception Empty ->  (ANSITerminal.(print_string [red]  
                                           "Please enter a command.\n")); 
      loopgame game st json true
    | exception Malformed -> 
      (ANSITerminal.(print_string [red]  
                       "Malformed command. Please use available commands.\n")); 
      loopgame game st json true
    | your_command ->  (match your_command with
        | Quit -> print_endline "Bye!"; exit 0
        | Pass -> 
          ignore(Sys.command "clear");
          print_endline ("Player " ^ (State.current_player st |> string_of_int) 
                         ^ " has passed."); 
          begin match pass st with 
            | Legal st' -> loopgame game st' json false
            | Illegal s-> loopgame game st json true
          end
        | Create w -> 
          if List.mem_assoc (String.uppercase_ascii w) 
              (State.current_player_wordlist st) 
          then ((ANSITerminal.(print_string [red] 
                                 "This word has already been created.\n"); 
                 loopgame game st json true))
          else 
            begin match create w st false with
              | Illegal s-> 
                (ANSITerminal.(print_string [red] s); 
                 loopgame game st json true)
              | Legal st' -> ignore(Unix.sleep 2);ignore(Sys.command "clear"); 
                loopgame game st' json false
            end
        | Swap l -> let target = String.uppercase_ascii l in 
          if List.mem target (set |> Game.get_letters) then begin
            match swap l st json with 
            | Illegal s-> print_endline s; loopgame game st json true;
            | Legal st' -> 
              ignore(Unix.sleep 2);
              ignore(Sys.command "clear");
              loopgame game st' json false end
          else begin
            (ANSITerminal.(print_string [red]  
                             "This letter is not in your letter set. 
                             Please try again.\n"); 
             loopgame game st json true)
          end
        |_ -> ANSITerminal.(print_string [red] "Malformed command. 
        Please use available commands.\n"; 
                            loopgame2 game st json true)
      )

  )

(** [ask_configure()] is [true] iff the player chooses to configure. *)
let rec ask_configure() = 
  print_endline "Would you like to configure your game? (answer yes or no)"; 
  print_string "> "; 
  match read_line() with
  | "yes" -> true
  | "no" -> false
  | _ -> print_endline "ERROR. Enter 'yes' or 'no' "; 
    ask_configure()


(** [ask_players] prompts the player for the number of players, and returns
    that number to the initial state. *)
let rec ask_players() = 
  print_endline "How many players: "; 
  print_string "> "; 
  match parse_number (read_line()) with
  | 0 -> print_endline "ERROR. Enter a valid number of players: "; 
    ask_players()
  | x -> x

(** [ask_num_letters()] prompts the player for the number of letters for the 
    turns, and returns that number to the initial state.*)
let rec ask_num_letters() = 
  print_endline "How many letters (max 10): "; 
  print_string "> "; 
  match parse_number (read_line()) with
  | 0 -> print_endline "ERROR. Enter a valid number: "; 
    ask_num_letters()
  | x -> if x > 10 then 
      ask_num_letters() else x

(** [ask_turns()] prompts the player for the number of turns, and returns that 
    number to the initial state. *)
let rec ask_turns() = 
  print_endline "How many turns per player: "; 
  print_string "> "; 
  match parse_number (read_line()) with
  | 0 -> print_endline "ERROR. Enter a valid number: "; 
    ask_num_letters()
  | x -> x

(** [ask_mode()] prompts the player for the game mode, and returns that 
    string to the initial state.*)
let rec ask_mode() = 
  print_endline "Which game mode (normal, pool): "; 
  print_string "> "; 
  match read_line() with
  | "normal" -> "normal"
  | "pool" -> "pool"
  | _ -> print_endline "ERROR. Enter a valid game mode: ";
    ask_mode()


(** [play_game j] starts the game with the letter set generated from the 
    alphabet in file [j]. *)
let play_game j = 
  let json = match Yojson.Basic.from_file j with
    | exception Sys_error s -> failwith ("Your input failed. " 
                                         ^ s ^ ". Start the game over. ")
    | _ -> Yojson.Basic.from_file j
  in print_endline "The default settings for the game are: ";
  print_endline "-> 6 letters, 2 players, 5 turns per player, normal mode <-";
  let config = ask_configure() in
  if config then
    let num_words = ask_num_letters() in
    let alpha = all_letters (from_json json) in
    let our_game = combo_set_var (from_json json) num_words in
    let num_players = ask_players() in
    let num_turns = ask_turns() in 
    let game_mode = ask_mode() in
    let initst = init_state our_game num_players num_turns game_mode alpha in 
    if game_mode = "normal" then begin
      ignore(Sys.command "clear");
      ANSITerminal.(print_string [red] 
                      "GAME MODE: NORMAL \n \n"); 
      loopgame our_game initst json false
    end
    else begin
      ignore(Sys.command "clear");
      ANSITerminal.(print_string [red] 
                      "GAME MODE: POOL \n \n"); 
      loopgame2 our_game initst json false
    end
  else begin
    ignore(Sys.command "clear");
    let our_game = combo_set_var (from_json json) 6 in
    let alpha = all_letters (from_json json) in
    let initst = init_state our_game 2 5 "normal" alpha in
    loopgame our_game initst json false end


(** [main ()] prompts for the game to play, then starts it. *)
let main () = 
  ignore(Sys.command "resize -s 30 80");
  ignore(Sys.command "clear");
  ANSITerminal.(print_string [red]
                  "\n\nWelcome to ANAGRAMS.\n");
  print_endline
    "Please enter the name of the game alphabet file you want to load.\n";
  print_string  "> ";
  match read_line () with
  | exception End_of_file -> ()
  | file_name -> play_game file_name

(* Execute the game engine. *)
let () = main ()
