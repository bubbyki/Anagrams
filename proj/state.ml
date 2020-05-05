open Command
open Game

type player = {   
  player_words:(Command.word * Game.points) list;
  total_points: Game.points;
  player_letter_set: Game.t;
  current_letter: string;
  swaps: float;
}

type player_id = int

type  t = {
  turns_left: int;
  player_list: (player_id  * player) list;
  current_player: player_id;
  total_players: int;
  mode: string;
  set: Game.t;
  alpha: Game.all_letters_in_json
}

type result = Legal of t | Illegal of string

(** [random_letter ()] is a random uppercase letter from the English alphabet.*)
let random_letter () = 
  Char.escaped (Char.chr ((Random.self_init(); Random.int 26) + 65))

(** [init_player] initializes a player *)
let init_player set = {
  player_words = [];
  total_points = 0;
  player_letter_set = set;
  current_letter = random_letter();
  swaps = 0.;
}

let init_state set num turn mode a = {
  turns_left= turn * num; 
  player_list = List.init num (fun i -> ((i + 1), init_player set));
  current_player = 1;
  total_players = num;
  mode = mode;
  set= set;
  alpha = a
}

let turns state = 
  state.turns_left

let state_alpha state = 
  state.alpha

let current_player state = 
  state.current_player

let current_player_wordlist state =  
  (List.assoc state.current_player state.player_list).player_words

let current_player_points state = 
  (List.assoc state.current_player state.player_list).total_points

let current_player_letter_set state =
  (List.assoc state.current_player state.player_list).player_letter_set

(** [current_player_letter st] is the current player's letter at state [st]. *)
let current_player_letter st = 
  (List.assoc st.current_player st.player_list).current_letter

let player_count state = 
  state.total_players

let get_pool st = st.set

let next_player state = 
  if (not (state.current_player = state.total_players))
  then state.current_player + 1 
  else 1

(**[word_to_cl n] is a char list of the input [word].*)
let word_to_cl n = List.init (String.length n) (String.get n)

(**[cl_to_ll cl] is a string list of char list [cl], with all letters in 
   uppercase.*)
let cl_to_ll cl = List.map (fun x -> Char.escaped x) cl 
                  |> List.map String.uppercase_ascii

let calculate_word_points word st : Game.points= 
  let a = state_alpha st in
  let base = List.fold_left 
      (fun x y -> x + Game.get_points a y) 0 (word |> word_to_cl |> cl_to_ll) in 
  let length = String.length word in 
  if length >= 3 && length < 5 
  then base |> float_of_int |> (fun x -> x*. 1.2) |> int_of_float
  else if length >= 5 
  then base |> float_of_int |> (fun x -> x*. 1.5) |> int_of_float
  else base

(** [remove_invalid next_player inv_words state] is a player with all invalid 
    words removed from his words list*)
let rec remove_invalid next_player inv_words state = 
  match inv_words with
  | [] -> next_player
  | h :: t -> (if List.mem_assoc h (next_player.player_words) 
               then (let new_next_pwlst = 
                       List.remove_assoc h (next_player.player_words) in 
                     remove_invalid ({next_player with 
                                      player_words = new_next_pwlst; 
                                      total_points = 
                                        next_player.total_points - 
                                        calculate_word_points h state;
                                      player_letter_set = 
                                        next_player.player_letter_set;
                                      current_letter = ""}) 
                       t state)
               else remove_invalid next_player t state)

let calculate_swap_points state = 
  let id = state.current_player in 
  let player = List.assoc id state.player_list in 
  let swaps = player.swaps in 
  (-.(5. +. (1.5**swaps))) |> Float.round |> int_of_float

(* [action_message a w p] prints information about word [w] and the points [p]
   gained or lost as a result of action [a]*)
let action_message a w p = begin
  let p' = string_of_int (abs p) in
  let message = 
    if a = "swap" then ("\n'"^w^"' has been swapped. You've lost "^p'^" points.\n")
    else if p > 0 && (a = "create" || a = "steal") then  ("\n'"^w^"' has been created. You've gained "^p'^" points.\n")
    else "" in print_endline message; end

(** [update_player_list state ns players word action id] is the player_list 
    as a result of [action] being executed on player whose id is [id] in [state]. 
    The player takes the letter set [ns]. 
      If [action] = "steal" or "check", [word] is removed from [id]'s word list. 
         [action] = "swap", [word] is the letter swapped out of [id]'s. 
         [action] = "create", [word] is added to [id]'s word list. *)
let rec update_player_list state ns players word action id  = 
  match players with
  | [] -> [] 
  | (k,v)::t -> if k = id 
    then 
      let raw_pts = calculate_word_points word state in 
      let words = String.uppercase_ascii word in
      let actual_pts = if action = "swap" then calculate_swap_points state
        else if action = "check" || action = "steal" then -raw_pts 
        else raw_pts in 
      action_message action words actual_pts; 
      let player = {
        player_words = if action = "steal" || action = "check" then 
            let p = List.mem_assoc words v.player_words in 
            if p = true then List.remove_assoc words v.player_words else 
              List.remove_assoc words v.player_words
          else if not (words = "") 
          then List.append v.player_words [(words,actual_pts)]
          else v.player_words;
        total_points = v.total_points + actual_pts;
        player_letter_set = ns;
        current_letter = if action = "check" then "" else random_letter();
        swaps = if action = "swap" then v.swaps +. 1. else v.swaps
      } in (k,player)::(update_player_list state ns t word action id)
    else (k,v)::(update_player_list state ns t word action id)

(**[remove x lst acc] is [lst] with the first occurance of [x] removed. *)
let rec remove x lst acc = match lst with
  | [] -> acc
  | h::t -> if h = x then acc @ t else remove x t (h::acc)

(**[check_illegal ll combo_l] is [true] iff [ll] contains letter(s) that is not
   in the combo or more occurances of some letter offered in the combo. *)
let rec check_illegal ll combo_l = 
  match ll with 
  | [] -> false
  | h :: t -> if not (List.mem h combo_l) then true
    else check_illegal t (remove h combo_l [])

(**[check_letter_used st word] is [true] iff [word] contains the player's 
   current letter in [st]. *)
let check_letter_used st word = String.contains (String.uppercase_ascii word)
    (String.get (current_player_letter st) 0) 


(** [string_to_sl s i] is the string list of [s], where [i] is the
    length of the string subtracted by 1. All in uppercase. *)
let rec string_to_sl s i = let ups = String.uppercase_ascii s in
  if i>(-1) then 
    String.make 1 (String.get ups i) ::string_to_sl ups (i-1) else [] 

let create word state s = 
  let combo = (if state.mode = "pool" 
               then (current_player_letter state)::(Game.get_letters (get_pool state))
               else Game.get_letters (current_player_letter_set state)) in
  if word = "" then Illegal "Please enter a word."
  else if (s=false) && (check_illegal (word |> word_to_cl |> cl_to_ll) combo) 
  then Illegal "This word cannot be constructed with the current letter set."
  else if state.mode = "pool" && not(check_letter_used state word)
  then Illegal ("The word '" ^ word ^ "' does not contain your letter.")
  else 
    let player = state.current_player in 
    let player_l = state.player_list in 
    let new_set = (List.assoc player player_l).player_letter_set in
    let new_player_l = update_player_list state new_set player_l word "create" player in
    let used_letters_l = string_to_sl word ((String.length word)-1) in
    Legal {
      state with 
      turns_left = state.turns_left - 1;
      player_list = new_player_l;
      current_player = next_player state;
      total_players = state.total_players;
      set = if state.mode = "pool" 
        then let n_pool = set_length state.set in
          let incomp_pool = remove_letter state.set used_letters_l in 
          replenish_pool incomp_pool n_pool state.alpha 
        else state.set
    } 

let pass state = if state.mode = "normal" then
    Legal { state with
            turns_left = state.turns_left - 1;
            current_player = next_player state;
          } 
  else let player = state.current_player in 
    let player_l = state.player_list in 
    let new_set = (List.assoc player player_l).player_letter_set in
    Legal { state with
            turns_left = state.turns_left - 1;
            player_list = 
              update_player_list state new_set player_l "" "pass"
                player;
            current_player = next_player state;
            set = 
              Game.add_in_pool state.set (current_player_letter state) 
                (state_alpha state)
          } 

let swap l state json = 
  let alphabet = from_json json in 
  let set = current_player_letter_set state in
  let player = state.current_player in 
  let player_l = state.player_list in
  let new_set = swap_letter alphabet l set in 
  Legal { state with
          turns_left = state.turns_left - 1;
          player_list = update_player_list state new_set player_l "" "swap" player;
          current_player = next_player state;
        }

let steal w nw p st = 
  let wup = String.uppercase_ascii w in
  let nwup = String.uppercase_ascii nw in 
  let player_l = st.player_list in 
  let player = List.assoc p player_l in
  let words = player.player_words in 
  let new_set = player.player_letter_set in
  if not (List.mem_assoc wup words) 
  then Illegal ("The word '" ^ w ^ "' is not in player " ^ string_of_int p ^ "'s word list.")
  else if not (check_letter_used st nw) 
  then Illegal ("The word '" ^ nw ^ "' does not contain your letter.")
  else if not ((String.length nwup) = ((String.length wup) + 1)) 
  then Illegal ("You cannot use letters in the pool to steal a word.")
  else Legal {st with player_list = update_player_list st new_set player_l wup "steal" p}

(** [winner_check_helper players winners winner_p] is the list of winners in 
    game of state [state] and the highest number of point achieved by a player 
    in that game.*)
let rec winner_check_helper players winners winner_p = 
  match players with 
  | [] -> (winners,winner_p)
  | (id,p)::t -> if p.total_points > winner_p 
    then winner_check_helper t (id::[]) p.total_points
    else if p.total_points = winner_p && (not (List.mem id winners))
    then winner_check_helper t (id::winners) winner_p 
    else winner_check_helper t winners winner_p 

let winner_check state =
  let state' = {state with current_player = 1;} in
  let p_list = state.player_list in 
  let win_id = state'.current_player in 
  let win_p = (List.assoc win_id p_list).total_points in
  winner_check_helper p_list (win_id::[]) win_p

(* =====Below is for check phase====== *)

let rec invalid word_lst game state =
  match word_lst with 
  | [] -> state 
  | (h::t) -> let id = next_player state in 
    let player_l = state.player_list in 
    let player = List.assoc id player_l in 
    let new_set =  player.player_letter_set in 
    let word = String.uppercase_ascii h in
    let player_l' = update_player_list state new_set player_l word "check" id in 
    invalid t game {state with player_list = player_l'}

let valid game state = 
  {state with current_player = state.current_player + 1}

let print_player_word_list state id = 
  let wl = (List.assoc id state.player_list).player_words in
  if wl = [] then print_string "No words yet.\n" else
    List.iter (fun (k,v)-> print_string k; print_newline ();) wl

let print_player_letter st = 
  print_string ("\nCurrent player's letter: " );
  ANSITerminal.(print_string [Bold;blue] ((current_player_letter st) ^ "\n\n"))

(** [print_all_player_word_list_helper st acc] is a helper function 
    that prints all player[id]'s word list. *)
let rec print_all_player_word_list_helper st acc : unit = 
  if (acc > List.length st.player_list) 
  then ()
  else begin print_string ("Player " ^ string_of_int acc ^ ": "); 
    print_player_word_list st acc;
    print_all_player_word_list_helper st (acc + 1) end

let print_all_player_word_list st = print_all_player_word_list_helper st 1

