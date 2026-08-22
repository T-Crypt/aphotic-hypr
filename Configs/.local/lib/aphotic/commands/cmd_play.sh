#!/usr/bin/env bash
# aphotic play — Play terminal games like hangman, snake, and number guessing
# @cmd: play
# @cmd.desc: Play terminal games like hangman, snake, and number guessing
# @cmd.group: FUN
# @cmd.opt: hangman         | Play hangman game
# @cmd.opt: snake           | Play snake game
# @cmd.opt: guess           | Play number guessing game

aphotic_cmd_play() {
    local game="${1:-}"

    case "$game" in
        hangman)
            source "${COMMANDS_DIR}/play/hangman.sh"
            aphotic_cmd_play_hangman
            ;;
        snake)
            source "${COMMANDS_DIR}/play/snake.sh"
            aphotic_cmd_play_snake
            ;;
        guess)
            source "${COMMANDS_DIR}/play/guess.sh"
            aphotic_cmd_play_guess
            ;;
        ""|-h|--help)
            cat <<HELP
Usage: aphotic play <game>

Available games:
  hangman    Play hangman game
  snake      Play snake game
  guess      Play number guessing game

Example:
  aphotic play hangman
  aphotic play snake
  aphotic play guess
HELP
            ;;
        *)
            aphotic_err "unknown game: $game"
            echo "Run 'aphotic play --help' to see available games." >&2
            return 1
            ;;
    esac
}