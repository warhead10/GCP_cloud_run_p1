from fastapi import FastAPI, HTTPException
from fastapi.responses import HTMLResponse
from pydantic import BaseModel
from typing import List, Optional

app = FastAPI()

# --- In-Memory Database ---
todo_db = []

# --- Data Models ---
class TodoItem(BaseModel):
    id: int
    title: str
    description: Optional[str] = None
    completed: bool = False

class TodoCreate(BaseModel):
    title: str
    description: Optional[str] = None

# --- Frontend Code (Embedded HTML/JS) ---
html_content = """
<!DOCTYPE html>
<html>
    <head>
        <title>FastAPI Todo</title>
        <style>
            body { font-family: sans-serif; max-width: 800px; margin: 0 auto; padding: 20px; }
            .todo-item { border: 1px solid #ddd; padding: 10px; margin: 10px 0; display: flex; justify-content: space-between; align-items: center; }
            .input-group { margin-bottom: 20px; padding: 20px; background: #f9f9f9; border-radius: 8px; }
            input { padding: 8px; margin-right: 10px; width: 200px; }
            button { padding: 8px 16px; cursor: pointer; background: #007bff; color: white; border: none; border-radius: 4px; }
            button.delete-btn { background: #dc3545; }
            button:hover { opacity: 0.9; }
        </style>
    </head>
    <body>
        <h1>My To-Do List</h1>
        
        <div class="input-group">
            <input type="text" id="titleInput" placeholder="Task Title">
            <input type="text" id="descInput" placeholder="Description (Optional)">
            <button onclick="addTodo()">Add Task</button>
        </div>

        <div id="todoList"></div>

        <script>
            const apiUrl = '/todos';

            async function fetchTodos() {
                const response = await fetch(apiUrl);
                const todos = await response.json();
                const listDiv = document.getElementById('todoList');
                listDiv.innerHTML = '';
                
                todos.forEach(todo => {
                    const div = document.createElement('div');
                    div.className = 'todo-item';
                    div.innerHTML = `
                        <div>
                            <strong>${todo.title}</strong>
                            <div style="color: #666; font-size: 0.9em;">${todo.description || ''}</div>
                        </div>
                        <button class="delete-btn" onclick="deleteTodo(${todo.id})">Delete</button>
                    `;
                    listDiv.appendChild(div);
                });
            }

            async function addTodo() {
                const title = document.getElementById('titleInput').value;
                const description = document.getElementById('descInput').value;
                
                if (!title) return alert('Title is required');

                await fetch(apiUrl, {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({ title, description })
                });
                
                document.getElementById('titleInput').value = '';
                document.getElementById('descInput').value = '';
                fetchTodos();
            }

            async function deleteTodo(id) {
                await fetch(`${apiUrl}/${id}`, { method: 'DELETE' });
                fetchTodos();
            }

            // Load todos on page start
            fetchTodos();
        </script>
    </body>
</html>
"""

# --- Endpoints ---

@app.get("/", response_class=HTMLResponse)
def read_root():
    """Serves the frontend HTML"""
    return html_content

@app.get("/todos", response_model=List[TodoItem])
def get_todos():
    return todo_db

@app.post("/todos", response_model=TodoItem)
def add_todo(todo: TodoCreate):
    new_id = 1 if not todo_db else todo_db[-1].id + 1
    new_todo = TodoItem(
        id=new_id,
        title=todo.title,
        description=todo.description,
        completed=False
    )
    todo_db.append(new_todo)
    return new_todo

@app.delete("/todos/{todo_id}")
def delete_todo(todo_id: int):
    for index, todo in enumerate(todo_db):
        if todo.id == todo_id:
            todo_db.pop(index)
            return {"message": "Todo deleted successfully"}
    raise HTTPException(status_code=404, detail="Todo not found")