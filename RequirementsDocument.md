# File Catalog Requirements Document

2026-10-31

## Overview

File Catalog is at it's core a file explorer application, to find and open documents. and supports all basic file operations like create new file, folder, copy and paste search and navigate files etc. The core diffrence is in the application focus and priority. While a standard file manager purpose is to allows users manage there files, moving, copying and accessing files, where File Catalog main purpose is organizing files and making large amounts of files easily  navigable and accessible.

In real world scenarios users may have folders for vendors, process documents, meetings notes, etc. a request or project comes in where for short time you need to link the documentation between these folders into a project, once the porject is closed you want to move the project documentation and outcome back to the main subject folder. Example negioting a renwal contract with and supplier, I want to open a topic or project folder, that contain the documents of the draft contract, old contract, ai recommendations links to other relevant documents web sites,and posbly emails. when done the project folder gets moved into the vendor folder as a sub folder.

while there are many dedicated content management applications for sorting and grouping your informations they tend to lock you in there solution of working. The idea of this applications is to make use of standard files/foldes stored on your desktop or cloud drives and link the information in away that remains workable enev with out this application.

File Catalog is designed as an ultra-fast, keyboard-driven, desktop file manager combining high performance, user friendly UI to provide an awesome experience for information workers to quickly find and sort files.

## User Requirements

- Application Layout

  - Full Menu Bar - all actions grouped in standard menu layout
  - Toolbar - Full customizable toolbar with quick accesable buttons
  - Bookmark Bar
  - Tab Bar
  - Address Bar - breadcomb mode
  - Dockable side bar, content container, and possible rigt quick view area.
  - Sidebar is used for switching between a tree view, standard favorites view, full bookmark view, or content aware bookmark view.
    - Content aware view: a side view of links to folders, documents and web sites that could be related to the folder you are looking at. Keep it minimal in the first version so the idea can take shape and evolve with the project.
  - Content container typical list files, name, created modified date, sync status
    - The standard file explorer columns are available and can be shown or hidden per view. Name, created and modified date, size and sync status are visible by default.
  - Status bar, number of files, folder, slece count, progress

- Sorting and filtering by filename, size, date

- Quick persist button to persest sorting and view layout per folder.

- Quick file filter - with in the current list files filter by name quickly, similiar to the excel filter function on a filtered table.

- Quick file find - search files and sub folders

- Create new folder, shortcut and file

- Create a file from a template file or folder

- Customizable shortcuts for all actions.

- Quick command bar similar to Ctrl + P in vscode.

- File operations

  - Copy
  - Move
  - Rename
  - Delete
  - Duplicate
  - Compress to ZIP and extract ZIP
  - Compare two files

- E-mails are handled as saved files (.eml, .msg) and work like any other file. No e-mail client integration in the first version.

  

## Technical requirements

- The application must be fast, open within 500ms, use caching and multithreading to give the user a responsive user experience. 
- Rust is the backend and UI container technology (chosen over Zig).
- ELM (version 0.19.3) must be used for UI front end development.
- File system access must run on separate threads so it never affects the UI; slow network locations get their own threads.
- Platforms: Windows is the primary platform, Linux is supported. macOS is not in the first version but must be kept in mind for later development.
- All application settings is saved in the user app folder in ini or toml format! Crtical to be easily human readiable.
- Folder specific settings are saved only in the app user settings folder, in the same file format. Nothing is written into the folders themselves.





