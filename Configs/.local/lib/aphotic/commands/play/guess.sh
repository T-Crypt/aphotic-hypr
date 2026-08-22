#!/usr/bin/env bash
# aphotic play guess — Play a number guessing game
# @cmd: play guess
# @cmd.desc: Play a number guessing game

aphotic_cmd_play_guess() {
    local min=1
    local max=100
    local target=$((RANDOM % (max - min + 1) + min))
    local attempts=0
    local guess=0

    clear

    echo "=== NUMBER GUESSING GAME ==="
    echo ""
    echo "I'm thinking of a number between $min and $max."
    echo "Can you guess what it is?"
    echo ""

    while true; do
        read -p "Enter your guess: " guess

        # Validate input
        if ! [[ "$guess" =~ ^[0-9]+$ ]]; then
            echo "Please enter a valid number!"
            continue
        fi

        attempts=$((attempts + 1))

        if [[ $guess -lt $target ]]; then
            echo "Too low! Try a higher number."
        elif [[ $guess -gt $target ]]; then
            echo "Too high! Try a lower number."
        else
            echo ""
            echo "Congratulations! You guessed the number in $attempts attempts!"
            echo "The number was: $target"
            break
        fi
    done

    echo ""
    echo "Thanks for playing!"
}