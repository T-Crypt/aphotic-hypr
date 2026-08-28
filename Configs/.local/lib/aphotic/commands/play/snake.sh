#!/usr/bin/env bash
# aphotic play snake — Play a game of snake in the terminal
# @cmd: play snake
# @cmd.desc: Play a game of snake in the terminal

aphotic_cmd_play_snake() {
    # Terminal control sequences
    local clear_screen='\033[2J'
    local hide_cursor='\033[?25l'
    local show_cursor='\033[?25h'
    local cursor_home='\033[H'

    # Always restore the cursor on the way out, however the game ends --
    # Ctrl+C previously left it hidden for the rest of the terminal
    # session since nothing ever ran $show_cursor on an interrupt.
    trap 'echo -ne "$show_cursor"' EXIT

    # Board fills the actual terminal ("play within the walls of the
    # current terminal"), not a fixed 20x15 -- `stty size` is the
    # reliable way to ask the tty directly (works even when $COLUMNS/
    # $LINES aren't exported into a script's environment), falling back
    # to tput and then a safe default if neither is available (e.g. stdin
    # isn't actually a tty). Clamped so a huge terminal doesn't turn into
    # an unplayably large board, and a tiny one still gets something
    # playable.
    local term_rows term_cols
    read -r term_rows term_cols < <(stty size 2>/dev/null) || true
    if [[ -z "$term_cols" ]] && command -v tput >/dev/null 2>&1; then
        term_cols="$(tput cols 2>/dev/null)" || true
        term_rows="$(tput lines 2>/dev/null)" || true
    fi
    term_cols="${term_cols:-80}"
    term_rows="${term_rows:-24}"

    local width=$((term_cols - 2))
    local height=$((term_rows - 4))  # top/bottom border + score line + a margin so the board never scrolls
    ((width < 10)) && width=10
    ((width > 60)) && width=60
    ((height < 8)) && height=8
    ((height > 25)) && height=25

    # Game constants
    local base_speed=200  # milliseconds between updates at score 0
    local min_speed=70    # never gets faster than this

    # Game state
    local snake_x=()
    local snake_y=()
    local snake_length=3
    local food_x=0
    local food_y=0
    local direction="right"
    local game_over=false
    local score=0
    local best_score
    best_score="$(_aphotic_play_best_score snake)"

    # Initialize game
    init_game() {
        # Clear screen and hide cursor
        echo -ne "$clear_screen$hide_cursor$cursor_home"

        # Initialize snake in the middle
        snake_x=($((width/2)) $((width/2)) $((width/2)))
        snake_y=($((height/2)) $((height/2)) $((height/2)))

        # Place initial food
        place_food

        # Set direction
        direction="right"
    }

    # Place food at random location
    place_food() {
        local valid_position=true
        local x=0
        local y=0

        while [[ $valid_position == true ]]; do
            x=$((RANDOM % width))
            y=$((RANDOM % height))

            valid_position=false

            # Check if position is on snake
            for ((i=0; i<snake_length; i++)); do
                if [[ ${snake_x[$i]} -eq $x && ${snake_y[$i]} -eq $y ]]; then
                    valid_position=true
                    break
                fi
            done
        done

        food_x=$x
        food_y=$y
    }

    # Draw game board
    draw_board() {
        echo -ne "$cursor_home"

        # Top border
        for ((i=0; i<width+2; i++)); do
            echo -ne "#"
        done
        echo ""

        # Game area
        for ((y=0; y<height; y++)); do
            echo -ne "#"
            for ((x=0; x<width; x++)); do
                local char=" "

                # Draw snake
                local is_snake=false
                for ((i=0; i<snake_length; i++)); do
                    if [[ ${snake_x[$i]} -eq $x && ${snake_y[$i]} -eq $y ]]; then
                        if [[ $i -eq 0 ]]; then
                            char="O"  # Head
                        else
                            char="o"  # Body
                        fi
                        is_snake=true
                        break
                    fi
                done

                # Draw food
                if [[ ! $is_snake && $x -eq $food_x && $y -eq $food_y ]]; then
                    char="*"
                fi

                echo -ne "$char"
            done
            echo "#"
        done

        # Bottom border
        for ((i=0; i<width+2; i++)); do
            echo -ne "#"
        done
        echo ""

        echo "Score: $score | Best: $best_score | Use WASD to move, Q to quit"
    }

    # Move snake
    move_snake() {
        # Save tail position (to remove it when snake grows)
        local tail_x=${snake_x[$((snake_length-1))]}
        local tail_y=${snake_y[$((snake_length-1))]}

        # Move body segments
        for ((i=snake_length-1; i>0; i--)); do
            snake_x[$i]=${snake_x[$((i-1))]}
            snake_y[$i]=${snake_y[$((i-1))]}
        done

        # Move head based on direction
        case "$direction" in
            "up")
                snake_y[0]=$((snake_y[0] - 1))
                ;;
            "down")
                snake_y[0]=$((snake_y[0] + 1))
                ;;
            "left")
                snake_x[0]=$((snake_x[0] - 1))
                ;;
            "right")
                snake_x[0]=$((snake_x[0] + 1))
                ;;
        esac

        # Check for collisions with walls
        if [[ ${snake_x[0]} -lt 0 || ${snake_x[0]} -ge $width || \
              ${snake_y[0]} -lt 0 || ${snake_y[0]} -ge $height ]]; then
            game_over=true
            return
        fi

        # Check for collisions with self
        for ((i=1; i<snake_length; i++)); do
            if [[ ${snake_x[0]} -eq ${snake_x[$i]} && ${snake_y[0]} -eq ${snake_y[$i]} ]]; then
                game_over=true
                return
            fi
        done

        # Check if snake ate food
        if [[ ${snake_x[0]} -eq $food_x && ${snake_y[0]} -eq $food_y ]]; then
            # Grow snake (add one segment to tail)
            snake_length=$((snake_length + 1))
            score=$((score + 10))

            # Place new food
            place_food
        fi
    }

    # Handle input
    handle_input() {
        local input=""

        # Read input without waiting for Enter. `|| true` matters: a
        # `-t` timeout with nothing typed (the common case, every single
        # tick with no keypress) makes `read` return non-zero, which
        # `aphotic`'s dispatcher's `set -e` would otherwise treat as a
        # real failure and kill the whole CLI process on the very first
        # tick -- this is why the game previously exited instantly
        # instead of ever drawing a frame.
        read -n1 -t 0.05 input || true

        case "$input" in
            "w"|"W")
                if [[ "$direction" != "down" ]]; then direction="up"; fi
                ;;
            "s"|"S")
                if [[ "$direction" != "up" ]]; then direction="down"; fi
                ;;
            "a"|"A")
                if [[ "$direction" != "right" ]]; then direction="left"; fi
                ;;
            "d"|"D")
                if [[ "$direction" != "left" ]]; then direction="right"; fi
                ;;
            "q"|"Q")
                game_over=true
                ;;
        esac
    }

    # Main game loop
    init_game

    while [[ "$game_over" == false ]]; do
        handle_input
        move_snake

        if [[ "$game_over" == false ]]; then
            draw_board
        fi

        # Wait for next update -- gets a little faster as the score
        # climbs (classic snake difficulty ramp), never below min_speed.
        local speed=$((base_speed - score))
        ((speed < min_speed)) && speed=$min_speed
        sleep "0.$(printf '%03d' "$speed")"
    done

    # Game over
    echo -ne "$show_cursor"
    clear
    echo "=== SNAKE GAME ==="
    echo ""
    echo "Game Over!"
    echo "Final Score: $score"
    if _aphotic_play_record_score snake "$score"; then
        echo "New best score!"
    else
        echo "Best Score: $(_aphotic_play_best_score snake)"
    fi
    echo ""
    echo "Press any key to continue..."
    read -n1 -s -t 10 || true
}
