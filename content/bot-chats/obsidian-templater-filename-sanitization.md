---
share: true
aliases:
  - Obsidian Templater Filename Sanitization
title: Obsidian Templater Filename Sanitization
URL: https://bagrounds.org/bot-chats/obsidian-templater-filename-sanitization
---
[Home](../index.md) > [Bot Chats](./index.md)  
# Obsidian Templater Filename Sanitization  
## [Meta.ai](https://www.meta.ai) Prompt  
> Can you write an obsidian templater script that will sanitize the file name? The result should be kabob-case and only contain lowercase alphanumeric characters and dashes. There should not be dashes at the start or end of the filename.  
  
## Response  
Here's a simple Obsidian Templater script that uses regular expressions to sanitize a filename:  
```JavaScript  
<%*  
  const filename = tp.file.title;  
  const sanitizedFilename = filename  
    .toLowerCase()  
    .replace(/[^a-z0-9]+/g, '-')  
    .replace(/^-+|-+$/g, '');  
  tp.file.rename(sanitizedFilename);  
%>  
```  
Let me explain what this script does:  
It gets the current filename from tp.file.title.  
It converts the filename to lowercase using the toLowerCase() method.  
It replaces all sequences of non-alphanumeric characters with a single dash using the replace() method with a regular expression.  
It removes any leading or trailing dashes from the filename using another replace() method with a regular expression.  
Finally, it renames the file to the sanitized filename using tp.file.rename().  
To use this script, simply create a new Templater template in Obsidian and paste the script into it. You can then run the template on any file to sanitize its filename.  
