# Terminal Games in Aphotic

Aphotic includes some fun terminal-based games accessible through the `aphotic play` command.

## Available Games

### 1. Hangman
Play the classic word guessing game:
```bash
aphotic play hangman
```

### 2. Snake
Control a snake to eat food and grow longer without hitting walls or yourself:
```bash
aphotic play snake
```

### 3. Number Guessing
Guess a randomly generated number between 1 and 100:
```bash
aphotic play guess
```

## How to Play

- **Hangman**: Use the keyboard to guess letters in the hidden word. Try to guess the word before making too many wrong guesses.
- **Snake**: Use WASD keys to control the snake's direction. Eat the food (*) to grow longer and increase your score. Avoid hitting walls or yourself.
- **Number Guessing**: Enter numbers to try to guess the secret number. The game will tell you if your guess is too high or too low.

## Requirements

All games are written in bash with no external dependencies beyond what's already included in Aphotic. They use terminal control sequences for display and input handling.