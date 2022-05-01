global function WordleInit;

struct GuessData {
	array<string> guesses
	bool finished = false
}

table<entity, GuessData> guessData = {};
string wordleAnswer;
string wordleWinners;
string blankCharacter;
string blankAnswer = "";
int maxGames;
int maxGuesses;

string wordleColourGreen = "\x1b[38;5;71m";
string wordleColourYellow = "\x1b[38;5;178m";
string wordleColourGrey = "\x1b[38;5;8m";
string wordleColourWhite = "\x1b[0m";
string wordleColourLightGrey = "\x1b[36m";
string formatSpace = "      ";

void function WordleInit() {
	AddCallback_OnReceivedSayTextMessage(WordleCheckGuess);
	if (GetConVarBool("wordle_share_at_map_end")) AddCallback_GameStateEnter(eGameState.WinnerDetermined, WordleShareServerResults);

	// Select our wordle word from the dictionary array
	// Randomise the word selection a little more as randomisation in northstar is pseudo-random
	wordleAnswer = wordleDictionaryAnswers.getrandom().toupper();

	blankCharacter = GetConVarString("wordle_blank_character");
	maxGuesses = GetConVarInt("wordle_guesses");
	if (maxGuesses < 3) maxGuesses = 3;	// Do not allow less than 3 guesses because keyboard will not display correctly

	// Split the word into individual letters, generate our blank-out string
	for (int i = 0; i < wordleAnswer.len(); i++) {
		blankAnswer += blankCharacter;
	}
}


ClServer_MessageStruct function WordleCheckGuess(ClServer_MessageStruct message) {
	string errorMessage = "";

	// Check if player has guessed before and if not, initialise their data
	if (!(message.player in guessData)) {
		GuessData playersGuess
		guessData[message.player] <- playersGuess;

		// player did not send correct number of letters - broadcast the blank game to them one time
		if (message.message.len() != wordleAnswer.len()) {
			SendInstructions(message.player);
			errorMessage = "A new WORDLE will be available each map!";
			DrawGame(message.player, false, errorMessage);
			return message;
		}
	}

	// Put player's guess into a sanitised string with all caps and no non-alphabetical characters
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

	// Ignore if player's text is not in allowed words
	if (wordleDictionaryAllowed.find(guess.tolower()) < 0 && wordleDictionaryAnswers.find(guess.tolower()) < 0) {
		errorMessage = guess + " is not a valid word";
		EmitSoundOnEntityOnlyToPlayer( message.player, message.player, "CoOp_SentryGun_DeploymentDeniedBeep" );
	}
	else {
		// If player is still in the game at this point, save their guess
		guessData[message.player].guesses.append(guess);
		EmitSoundOnEntityOnlyToPlayer( message.player, message.player, "UI_InGame_FD_ArmoryPurchase" );
	}

	// Draw a little divider blank space
	Chat_ServerPrivateMessage(message.player, "", true);
	DrawGame(message.player, false, errorMessage);	// Draw gamestate privately

	// Player won. Show them the win message and stop them from playing again
	if (guess == wordleAnswer) {
		guessData[message.player].finished = true;	// Stop the player from being able to play again

		// Add the player's result to the winners string
		if (wordleWinners.len() > 0) wordleWinners += ", ";
		wordleWinners += message.player.GetPlayerName() + " (" + guessData[message.player].guesses.len() + "/" + maxGuesses + ")";

		// Share player's result with the server
		Chat_ServerBroadcast(message.player.GetPlayerName() + " got this map's Wordle in " + guessData[message.player].guesses.len() + "/" + maxGuesses);
		DrawGame(message.player, true);
	}
	else if (guessData[message.player].guesses.len() >= maxGuesses) {
		// Player lost
		Chat_ServerBroadcast(message.player.GetPlayerName() + " did not guess this map's Wordle");
		DrawGame(message.player, true);
		Chat_ServerPrivateMessage(message.player, "The answer was " + wordleAnswer, true);
	}

	// Debug msg
	//printl(message.player.GetPlayerName() + " guessed " + guess + " - Answer is " + wordleAnswer);

	message.shouldBlock = true;
	return message;
}

/* Sends chat message or broadcast with wordle gamestate
		bool public if true, will broadcast
*/
void function DrawGame(entity player, bool public = false, string message = "") {
	// Server messages are lost if watching killcam.
	while(player.IsWatchingKillReplay()) WaitFrame();

	// Go through each of the player's guesses
	for (int i = 0; i < maxGuesses; i++) {

		string output = "";
		if (i < guessData[player].guesses.len()) { // Player has a guess within this row
			if (!public) output += FormatGuess(guessData[player].guesses[i], wordleAnswer);
			else output += FormatGuess(guessData[player].guesses[i], wordleAnswer, true);
		}
		else if (!public) output += blankAnswer; // Player has not guessed beyond this point - show them blank white squares

		if (public) {
			if (output.len() > 0) Chat_ServerBroadcast(output);
		}
		else {	// Append keyboard to player's private game
			output += FormatKeyboard(guessData[player].guesses, wordleAnswer, i, message);
			Chat_ServerPrivateMessage(player, output, true);
		}
	}

}

/* Format a guess against an answer.
		string guess contains the player's guess
		string answer the string to check against
		bool blank if true, retains the colours but replaces the letter with blank-out character
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
string function FormatKeyboard(array<string> guesses, string answer, int row, string message = "") {
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

			if (char == answerLetters[i]) l[char] = wordleColourGreen + char;
			else if (l[char] != wordleColourGreen + char) {
				if (answer.find(char) != null) l[char] = wordleColourYellow + char;
				else l[char] = wordleColourGrey + char;
			}

			i++;
		}
	}

	string output = "";
	// Order these by priority in case server has set low number of guesses
	if (row == maxGuesses - 3) output = formatSpace + formatSpace + l["Q"] + " " + l["W"] + " " + l["E"] + " " + l["R"] + " " + l["T"] + " " + l["Y"] + " " + l["U"] + " " + l["I"] + " " + l["O"] + " " + l["P"];
	else if (row == maxGuesses - 2) output = formatSpace + formatSpace + " " + l["A"] + " " + l["S"] + " " + l["D"] + " " + l["F"] + " " + l["G"] + " " + l["H"] + " " + l["J"] + " " + l["K"] + " " + l["L"];
	else if (row == maxGuesses - 1) output = formatSpace + formatSpace + "   " + l["Z"] + " " + l["X"] + " " + l["C"] + " " + l["V"] + " " + l["B"] + " " + l["N"] + " " + l["M"];
	else if (row == maxGuesses - 4) output = formatSpace + wordleColourLightGrey + message;
	else if (row == 0) output = formatSpace + wordleColourWhite + "-- " + GetMapName() + " " + GameRules_GetGameMode() + " Wordle --";
	return output;

}

/* Standardises input to allcaps and no special characters or spaces
		Expected output is string of player's message in all caps and no non-alphabetical characters removed
*/
string function CleanGuessInput(string input) {
	string output = "";

	// Make a list of acceptable characters
	string validCharacters = "abcdefghijklmnopqrstuvwxyz";
	validCharacters += validCharacters.toupper();

	array<string> characters = SplitStringToChars(input);
	foreach (string character in characters) {
		if (validCharacters.find(character) != null) output += character.toupper();
	}

	return output;
}

/* Take a string and return an array of characters
		Returns an array of strings containing 1 character each
*/
array<string> function SplitStringToChars(string input) {
	array<string> characters = [];
	for (int i = 0; i < input.len(); i++) {
		characters.append(input.slice(i, i+1));
	}
	return characters;
}

/* Send message to client with instructions on how to play
*/
void function SendInstructions(entity player) {
	Chat_ServerPrivateMessage(player, "Guess the WORDLE in " + maxGuesses + " tries. Each guess must be a valid " + wordleAnswer.len() + " letter word. Type in chat to submit.", false);
	Chat_ServerPrivateMessage(player, "After each guess, the color of the tiles will change to show how close your guess was to the word.", false);
	Chat_ServerPrivateMessage(player, "Examples", false);
	Chat_ServerPrivateMessage(player, "  " + wordleColourGreen + "W" + wordleColourWhite + "EARY - The letter W is in the word and in the correct spot.", false);
	Chat_ServerPrivateMessage(player, "  P" + wordleColourYellow + "I" + wordleColourWhite + "LLS - The letter I is in the word but in the wrong spot.", false);
	Chat_ServerPrivateMessage(player, "  VAG" + wordleColourGrey + "U" + wordleColourWhite + "E - The letter U is not in the word in any spot.", false);
}

/* Announce Wordle winners to the server
		Should be run at the end of the game on eGameState.WinnerDetermined
*/
void function WordleShareServerResults() {
	if (wordleWinners.len() > 0 &&
			(
				!IsRoundBased() ||
				(IsRoundBased() && GameRules_GetTeamScore2(GameScore_GetWinningTeam()) == GetRoundScoreLimit_FromPlaylist())
			)
		) {
		Chat_ServerBroadcast("Wordle winners: " + wordleWinners);
	}
}
