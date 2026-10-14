import json
import requests
import subprocess
import time
import sys
import os

# Function to send a prompt to the LLM and return the response.
def send_prompt_to_llm(prompt, model_name="gemma", max_retries=2, retry_delay=1):
    # Inside a sandbox, localhost is the sandbox itself, so read the Ollama
    # address from an environment variable and keep the old value as default.
    base = os.environ.get("OLLAMA_URL", "http://localhost:11434")
    url = f"{base}/api/generate"
    headers = {"Content-Type": "application/json"}
    data = json.dumps({"model": model_name, "prompt": prompt, "response_format": "json", "stream": False})

    for attempt in range(max_retries + 1):
        try:
            response = requests.post(url, headers=headers, data=data)
            response.raise_for_status()  # Raise an exception for bad status codes
            response_json = response.json()
            response_text = response_json['response']
            return response_text
        except (requests.RequestException, json.JSONDecodeError, KeyError) as e:
            if attempt < max_retries:
                print(f"Attempt {attempt + 1} failed. Retrying in {retry_delay} seconds...")
                time.sleep(retry_delay)
            else:
                print(f"All attempts failed. Last error: {str(e)}")
                raise  # Re-raise the last exception if all retries fail

    # This line should never be reached, but added for completeness. Exit in such case
    print("Error: Couldn't connect to the LLM.", file=sys.stderr)
    sys.exit(1)

#  Function to get the list of changed files in the current commit.
def get_changed_files():
    result = subprocess.run(["git", "diff", "HEAD^", "HEAD", "--name-only"], capture_output=True, text=True)
    changed_files = result.stdout.strip().split('\n')
    return changed_files

# Function to make a prompt for the LLM.
def make_prompt(rule, go_file):
    with open(go_file, 'r') as file:
        code = file.read()

    # Since LLMs need escaped code, we need to escape the code before sending it to the LLM.
    escaped_code = json.dumps(code)
    prompt = "Reply in True or False. I am passing a Go code. Does it follow the rule: " + rule + "?\n\n"
    prompt += "Here is my Go code: " + escaped_code + "\n\n"
    return prompt

if __name__ == "__main__":
    print("------------------------------------------------------------------------------------------------- \n")
    print(" (^_^) 🤖 [o_o] ⚡️ (^.^)✨ ** WELCOME TO YOUR CODE REVIEW BY AI **  ✨(^.^) ⚡️ [o_o] 🤖 (^_^) \n")
    print("------------------------------------------------------------------------------------------------- \n ")

    # an array of rules to check against
    rules = []

    with open('rules.md', 'r') as file:
        for line in file:
            # Strip whitespace and add non-empty lines to the rules array
            stripped_line = line.strip()
            if stripped_line:
                rules.append(stripped_line)

    print(" (☞ﾟヮﾟ)☞  AI will be checking your code changes against these rules 🔍: \n")
    for i, rule in enumerate(rules, 1):
        print(f"{i}. {rule}")

    print("------------------------------------------------------------------------------------------------- \n ")

    changed_files = get_changed_files()
    print("Changed files: ", changed_files)

    # Filter the files ending with .go at the end
    go_files = [file for file in changed_files if file.endswith('.go')]

    # If no changes made to the Go code no need to of code review
    if go_files == []:
        print("No changes found to any go file in this commit 😊 \n")
        print ("Adios Amigo! 👋")
        exit()

    print("🧐 In this job we will be checking these files:  \n")

    i =1    
    for file in go_files:
        print(f"{i}. {file}")
        i+=1

    print("------------------------------------------------------------------------------------------------- \n ")

    # Looping over the files and sending the prompt to the LLM
    for file in go_files:
        print(f" > 📁 {file} : \n")
        for rule in rules:
            prompt = make_prompt(rule, file)
            model_name = os.environ.get("LLM") # You can change the model name here
            response = send_prompt_to_llm(prompt, model_name)
            print(f"\n\n -> {rule}: {response} \n")
            print("................................................................................. \n ")
        print("------------------------------------------------------------------------------------------------- \n ")

