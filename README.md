# MATLAB Typewriter Package #
Contains a simple app for providing text prompts based on the Mackenzie & Soukoreff 2003 dataset. Quick start:  

```batch
git submodule add git@github.com:Neuro-Mechatronics-Interfaces/matlab_class__Typewriter.git +typewriter
git submodule update --init --recursive
```

## Overview
The **Prompter Typing Interface** is a MATLAB-based application designed for guided typing tasks. It provides real-time feedback for user input accuracy, tracks words-per-minute (WPM) performance, and supports automated prompt advancement.

The interface is implemented as a MATLAB class (`Prompter`) and includes a graphical user interface (GUI) built with `uifigure`. It is especially suited for typing-based experiments, training applications, or research studies.

## Features
- **Real-Time Typing Feedback**: 
  - Background colors dynamically update to indicate correct, incorrect, and incomplete text.
- **Words-Per-Minute Tracking**: 
  - Displays live WPM statistics based on typing speed.
- **Configurable Phrase Set**: 
  - Load custom typing prompts from a text file.
- **Auto-Advance Mode**: 
  - Automatically advances to the next prompt upon completion.
- **GUI Controls**:
  - Pause and resume functionality.
  - Integrated heads-up display (HUD) for WPM statistics.

## Interface
- **Main Typing Area**:
  - Displays the current prompt with background color feedback for each character.
  - Includes a text input box for user typing.
- **Right-Side HUD**:
  - Displays current WPM.
  - "Pause" button to stop typing and disable input temporarily.

## Installation
1. Clone or download the project to your local system.
2. Ensure MATLAB is installed (tested with MATLAB R2024a).
3. Place the project directory in your MATLAB path.

## Usage
### Basic Initialization
```matlab
% Create a Prompter instance with default settings
prompter = typewriter.Prompter();
