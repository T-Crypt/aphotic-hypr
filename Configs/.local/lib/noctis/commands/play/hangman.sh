#!/usr/bin/env bash
# noctis play hangman — Play a game of hangman in the terminal
# @cmd: play hangman
# @cmd.desc: Play a game of hangman in the terminal

noctis_cmd_play_hangman() {
    # Word list for hangman
    local words=("python" "computer" "programming" "terminal" "linux" "bash"
                 "hyprland" "wallpaper" "theme" "quickshell" "noctis" "developer"
                 "keyboard" "mouse" "monitor" "software" "hardware" "network")

    # Hangman drawing parts
    local hangman_parts=(
        "  +---+"
        "  |   |"
        "      |"
        "      |"
        "      |"
        "      |"
        "========="
    )

    # Get a random word
    local word="${words[RANDOM % ${#words[@]}]}"
    local word_len=${#word}

    # Initialize game state
    local guessed=""
    local wrong_guesses=0
    local max_wrong=6
    local guessed_word=""

    # Initialize guessed word with underscores
    for ((i=0; i<word_len; i++)); do
        guessed_word="${guessed_word}_ "
    done

    # Game loop
    while [[ $wrong_guesses -lt $max_wrong ]]; do
        # Clear screen and display game state
        clear

        echo "=== HANGMAN ==="
        echo ""

        # Display hangman
        for ((i=0; i<${#hangman_parts[@]}; i++)); do
            if [[ $i -lt $((wrong_guesses + 3)) ]]; then
                echo "${hangman_parts[$i]}"
            else
                echo "      |"
            fi
        done

        echo ""
        echo "Word: $guessed_word"
        echo "Wrong guesses: $wrong_guesses/$max_wrong"
        echo "Guessed letters: $guessed"
        echo ""

        # Get player input
        read -p "Guess a letter: " -n1 letter
        echo ""

        # Validate input
        if [[ ! "$letter" =~ ^[a-zA-Z]$ ]]; then
            echo "Please enter a single letter!"
            sleep 1
            continue
        fi

        letter="${letter,,}"

        # Check if already guessed
        if [[ "$guessed" == *"$letter"* ]]; then
            echo "You already guessed that letter!"
            sleep 1
            continue
        fi

        # Add to guessed letters
        guessed="${guessed}${letter}"

        # Check if letter is in word
        local found=false
        local new_word=""
        local i=0

        while [[ $i -lt $word_len ]]; do
            local char="${word:$i:1}"
            if [[ "${char,,}" == "${letter,,}" ]]; then
                new_word="${new_word}${char} "
                found=true
            else
                if [[ "${guessed_word:$((i*2)):1}" != "_" ]]; then
                    new_word="${new_word}${guessed_word:$((i*2)):1} "
                else
                    new_word="${new_word}_ "
                fi
            fi
            i=$((i+1))
        done

        guessed_word="$new_word"

        if [[ "$found" == false ]]; then
            wrong_guesses=$((wrong_guesses + 1))
        fi

        # Check win condition
        if [[ ! "$guessed_word" =~ "_" ]]; then
            clear
            echo "=== HANGMAN ==="
            echo ""
            for ((i=0; i<${#hangman_parts[@]}; i++)); do
                echo "${hangman_parts[$i]}"
            done
            echo ""
            echo "Congratulations! You won!"
            echo "The word was: $word"
            return 0
        fi
    done

    # Game over - player lost
    clear
    echo "=== HANGMAN ==="
    echo ""

    # Display full hangman
    for ((i=0; i<${#hangman_parts[@]}; i++)); do
        echo "${hangman_parts[$i]}"
    done

    echo ""
    echo "Game over! You lost!"
    echo "The word was: $word"
}