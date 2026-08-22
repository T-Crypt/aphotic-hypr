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

    # Game constants
    local width=20
    local height=15
    local speed=200  # milliseconds between updates

    # Game state
    local snake_x=()
    local snake_y=()
    local snake_length=3
    local food_x=0
    local food_y=0
    local direction="right"
    local game_over=false
    local score=0

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

        echo "Score: $score | Use WASD to move, Q to quit"
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

        # Read input without waiting for Enter
        read -n1 -t 0.05 input

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
            sleep 0.001  # Small delay for screen refresh
        fi

        # Wait for next update
        sleep 0.$speed
    done

    # Game over
    echo -ne "$show_cursor"
    clear
    echo "=== SNAKE GAME ==="
    echo ""
    echo "Game Over!"
    echo "Final Score: $score"
    echo ""
    echo "Press any key to continue..."
    read -n1 -s
}