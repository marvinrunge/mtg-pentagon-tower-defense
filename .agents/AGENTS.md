# Godot Verification Rule

Whenever you make changes to the Godot project's source code or scenes, you must automatically verify the build and runtime integrity before completing your task. 

To do this, use your `run_command` tool to execute:
```powershell
C:\Godot\godot.exe --headless --quit > godot_stdout.log 2> godot_stderr.log
```

Then, use your `view_file` tool to read `godot_stderr.log` to check for any GDScript parse errors or crash logs. If you find any script errors, you must fix them immediately. Finally, delete the temporary log files.
