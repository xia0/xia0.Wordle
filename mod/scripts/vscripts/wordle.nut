global function WordleInit;

struct GuessData {
	array<string> guesses
	bool finished = false
}

table<entity, GuessData> guessData = {};
string wordleAnswer;
string blankCharacter;
string blankAnswer = "";
array<string> wordleAnswerArray;
int maxGames;
int maxGuesses;

string wordleColourGreen = "\x1b[38;2;103;165;97m";
string wordleColourYellow = "\x1b[38;2;195;174;85m";
string wordleColourGrey = "\x1b[38;2;71;75;77m";
string wordleColourWhite = "\x1b[38;2;254;254;254m";
string wordleColourLightGrey = "\x1b[38;2;166;209;228m";

string formatSpaceBeforeWord = "                 ";
string formatSpaceBeforeKeyboard = "      ";
string formatHorizontalLine = "--------------------------";

void function WordleInit() {
	AddCallback_OnReceivedSayTextMessage(WordleCheckGuess);

	wordleAnswer = wordleDictionaryAnswers[rndint(wordleDictionaryAnswers.len())].toupper();
	blankCharacter = GetConVarString("wordle_blank_character");
	maxGuesses = GetConVarInt("wordle_guesses");

	// Split the word into individual letters
	for (int i = 0; i < wordleAnswer.len(); i++) {
		wordleAnswerArray.append(wordleAnswer.slice(i, i+1));
		blankAnswer += blankCharacter;
	}
}


ClServer_MessageStruct function WordleCheckGuess(ClServer_MessageStruct message) {

	// Check if player has guessed before and if not, initialise their data
	if (!(message.player in guessData)) {
		GuessData playersGuess
		guessData[message.player] <- playersGuess;

		// player did not send correct number of letters - broadcast the blank game to them one time
		if (message.message.len() != wordleAnswer.len()) {
			Chat_ServerPrivateMessage(message.player, "Guess the WORDLE in " + maxGuesses + " tries.", false);
			Chat_ServerPrivateMessage(message.player, "Each guess must be a valid " + wordleAnswer.len() + " letter word. Type in chat to submit.", false);
			Chat_ServerPrivateMessage(message.player, "After each guess, the color of the tiles will change to show how close your guess was to the word.", false);
			Chat_ServerPrivateMessage(message.player, "Examples", false);
			Chat_ServerPrivateMessage(message.player, wordleColourGreen + "W" + wordleColourWhite + "EARY", false);
			Chat_ServerPrivateMessage(message.player, "The letter W is in the word and in the correct spot.", false);
			Chat_ServerPrivateMessage(message.player, "P" + wordleColourYellow + "I" + wordleColourWhite + "LLS", false);
			Chat_ServerPrivateMessage(message.player, "The letter I is in the word but in the wrong spot.", false);
			Chat_ServerPrivateMessage(message.player, "VAG" + wordleColourGrey + "U" + wordleColourWhite + "E", false);
			Chat_ServerPrivateMessage(message.player, "The letter U is not in the word in any spot.", false);
			Chat_ServerPrivateMessage(message.player, "A new WORDLE will be available each map!", false);
			return message;
		}
	}

	// Put player's guess into a string
	string guess = CleanGuessInput(message.message);

	// Check if player has already finished playing
	if (guessData[message.player].guesses.len() >= maxGuesses || guessData[message.player].finished) {

		// See if player is saying the answer maybe with other characters between
		if (guess.find(wordleAnswer) != null) {
			message.shouldBlock = true;
		}
		return message;
	}

	// If saying a string of incorrect length, just ignore - probs a normal chat msg
	if (guess.len() != wordleAnswer.len()) return message;

	// Past this point, user is playing
	string errorMessage = formatHorizontalLine;

	// Ignore if player's text is not in allowed words
	if (wordleDictionaryAllowed.find(guess.tolower()) < 0 && wordleDictionaryAnswers.find(guess.tolower()) < 0) {
		//Chat_ServerPrivateMessage(message.player, guess + " is not a valid word", false);
		errorMessage = guess + " is not a valid word";
		message.shouldBlock = true;
	}
	else {
		// If player is still in the game at this point, save their guess
		guessData[message.player].guesses.append(guess);
	}


	// Put a divider
	Chat_ServerPrivateMessage(message.player, "-- " + GetMapName() + " " + GameRules_GetGameMode() + " Wordle --", true);
	DrawGame(message.player, false, errorMessage);	// Draw gamestate privately

	// Player won. Show them the win message and stop them from playing again
	if (guess == wordleAnswer) {
		//Chat_ServerPrivateMessage(message.player, guessData[message.player].guesses.len() + "/" + maxGuesses, false);
		guessData[message.player].finished = true;	// Stop the player from being able to play again

		// Share player's result with the server
		Chat_ServerBroadcast(message.player.GetPlayerName() + " got this map's Wordle in " + guessData[message.player].guesses.len() + "/" + maxGuesses);
		DrawGame(message.player, true);
	}
	else if (guessData[message.player].guesses.len() >= maxGuesses) {
		Chat_ServerBroadcast(message.player.GetPlayerName() + " did not guess this map's Wordle");
		DrawGame(message.player, true);
		Chat_ServerPrivateMessage(message.player, "The answer was " + wordleAnswer, true);
	}

	message.shouldBlock = true;
	return message;
}

/* Sends chat message or broadcast with wordle gamestate
*/
void function DrawGame(entity player, bool public = false, string message = "") {
	// Go through each of the player's guesses
	for (int i = 0; i < maxGuesses; i++) {

		if (i < guessData[player].guesses.len()) {	// Player has a guess within this row
			if (!public) {
				Chat_ServerPrivateMessage(player, formatSpaceBeforeWord + FormatGuess(guessData[player].guesses[i], wordleAnswer), true);
			}
			else Chat_ServerBroadcast(FormatGuess(guessData[player].guesses[i], wordleAnswer, true));
		}
		else { // Player has not guessed beyond this point
			if (!public) Chat_ServerPrivateMessage(player, formatSpaceBeforeWord + blankAnswer, true);
		}

	}

	// Draw keyboard for player
	if (!public) {
		Chat_ServerPrivateMessage(player, wordleColourLightGrey + message, true);
		Chat_ServerPrivateMessage(player, FormatKeyboard(guessData[player].guesses, wordleAnswer, 0), true);
		Chat_ServerPrivateMessage(player, FormatKeyboard(guessData[player].guesses, wordleAnswer, 1), true);
		Chat_ServerPrivateMessage(player, FormatKeyboard(guessData[player].guesses, wordleAnswer, 2), true);
	}
}

/* Return a one line colourised string
*/
string function FormatGuess(string guess, string answer, bool blank = false) {

	array<string> answerLetters = SplitStringToChars(answer);
	array<string> guessLetters = SplitStringToChars(guess);

	int i = 0;
	string response = "";
	foreach (string letter in guessLetters) {

		// Format which colour the letter should be
		if (letter == answerLetters[i]) response += wordleColourGreen;
		else if (answer.find(letter) != null)	response += wordleColourYellow;
		else response += wordleColourGrey;

		// Should we blank out the letters for sharing?
		if (!blank) response += guessLetters[i];
		else response += blankCharacter;

		i++
	}
	return response;
}

/* Provides the specified row of the keyboard given the guesses and answer
*/
string function FormatKeyboard(array<string> guesses, string answer, int row) {
	table<string, string> l = {
		A = wordleColourWhite + "A",
		B = wordleColourWhite + "B",
		C = wordleColourWhite + "C",
		D = wordleColourWhite + "D",
		E = wordleColourWhite + "E",
		F = wordleColourWhite + "F",
		G = wordleColourWhite + "G",
		H = wordleColourWhite + "H",
		I = wordleColourWhite + "I",
		J = wordleColourWhite + "J",
		K = wordleColourWhite + "K",
		L = wordleColourWhite + "L",
		M = wordleColourWhite + "M",
		N = wordleColourWhite + "N",
		O = wordleColourWhite + "O",
		P = wordleColourWhite + "P",
		Q = wordleColourWhite + "Q",
		R = wordleColourWhite + "R",
		S = wordleColourWhite + "S",
		T = wordleColourWhite + "T",
		U = wordleColourWhite + "U",
		V = wordleColourWhite + "V",
		W = wordleColourWhite + "W",
		X = wordleColourWhite + "X",
		Y = wordleColourWhite + "Y",
		Z = wordleColourWhite + "Z"
	};

	array<string> answerLetters = SplitStringToChars(answer);

	foreach (string guess in guesses) {
		array<string> guessLetters = SplitStringToChars(guess);
		int i = 0;
		foreach (string char in guessLetters) {

			if (answer.find(char) != null) l[char] = wordleColourYellow + char;
			else l[char] = wordleColourGrey + char;
			if (char == answerLetters[i]) l[char] = wordleColourGreen + char;

			i++;
		}
	}

	string output = "";
	if (row == 0) output = 			formatSpaceBeforeKeyboard + l["Q"] + " " + l["W"] + " " + l["E"] + " " + l["R"] + " " + l["T"] + " " + l["Y"] + " " + l["U"] + " " + l["I"] + " " + l["O"] + " " + l["P"];
	else if (row == 1) output = formatSpaceBeforeKeyboard + " " + l["A"] + " " + l["S"] + " " + l["D"] + " " + l["F"] + " " + l["G"] + " " + l["H"] + " " + l["J"] + " " + l["K"] + " " + l["L"];
	else if (row == 2) output = formatSpaceBeforeKeyboard + "   " + l["Z"] + " " + l["X"] + " " + l["C"] + " " + l["V"] + " " + l["B"] + " " + l["N"] + " " + l["M"];
	return output;

}

/* Standardises input to allcaps and no special characters or spaces
*/
string function CleanGuessInput(string input) {
	string output = "";

	// Make a list of acceptable characters
	string validCharacters = "abcdefghijklmnopqrstuvwxyz";
	validCharacters += validCharacters.toupper();

	array<string> characters = [];	// Load up player's guess into an array
	for (int i = 0; i < input.len(); i++) {
		characters.append(input.slice(i, i+1));
	}

	foreach (string character in characters) {
		if (validCharacters.find(character) != null) output += character.toupper();
	}

	return output;
}

/* Take a string and return an array of characters
*/
array<string> function SplitStringToChars(string input) {
	array<string> characters = [];	// Load up player's guess into an array
	for (int i = 0; i < input.len(); i++) {
		characters.append(input.slice(i, i+1));
	}
	return characters;
}
