---  
share: true  
aliases:  
  - <% tp.user.format_title(tp.file.title) %>  
title: <% tp.user.format_title(tp.file.title) %>  
URL:   
Author:   
tags:   
---  
<% [...['/index | home', ...tp.file.folder(true).split('/')].map(x =>  `[[${x}]]`), tp.user.format_title(tp.file.title)].join(' > ') %>  
# <% tp.user.format_title(tp.file.title) %>  
