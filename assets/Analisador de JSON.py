import json
import tkinter as tk
from tkinter import ttk, filedialog, messagebox
import pandas as pd

data = {}


# ----------------------------
# Carregar JSON
# ----------------------------
def carregar_json():
    global data
    caminho = filedialog.askopenfilename(filetypes=[("JSON files", "*.json")])
    if not caminho:
        return

    try:
        with open(caminho, encoding="utf-8") as f:
            data = json.load(f)

        montar_arvore()
        messagebox.showinfo("Sucesso", "JSON carregado!")
    except Exception as e:
        messagebox.showerror("Erro", str(e))


# ----------------------------
# Montar árvore
# ----------------------------
def montar_arvore():
    tree.delete(*tree.get_children())

    for colecao, itens in data.items():
        no_colecao = tree.insert("", "end", text=colecao, open=False)

        for i, (codigo, info) in enumerate(itens.items()):
            tree.insert(no_colecao, "end", text=codigo, values=(colecao,))

            if i > 200:  # evita travar com muitos itens
                break


# ----------------------------
# Mostrar detalhes
# ----------------------------
def mostrar_detalhes(event):
    item = tree.focus()
    codigo = tree.item(item, "text")
    valores = tree.item(item, "values")

    if not valores:
        return

    colecao = valores[0]

    if colecao in data and codigo in data[colecao]:
        info = data[colecao][codigo]

        texto.delete(1.0, tk.END)
        texto.insert(tk.END, json.dumps(info, indent=2, ensure_ascii=False))


# ----------------------------
# Buscar código
# ----------------------------
def buscar():
    codigo = entry_busca.get()

    resultado.delete(1.0, tk.END)

    for colecao, itens in data.items():
        if codigo in itens:
            resultado.insert(tk.END, f"\nEncontrado em {colecao}:\n")
            resultado.insert(tk.END, json.dumps(itens[codigo], indent=2, ensure_ascii=False))


# ----------------------------
# Encontrar relações
# ----------------------------
def relacoes():
    item = tree.focus()
    codigo = tree.item(item, "text")
    valores = tree.item(item, "values")

    if not valores:
        messagebox.showwarning("Aviso", "Selecione um item válido.")
        return

    colecao = valores[0]

    janela = tk.Toplevel(root)
    janela.title("Relações")
    janela.geometry("500x400")

    texto_rel = tk.Text(janela)
    texto_rel.pack(fill="both", expand=True)

    # ----------------------------
    # CASO 1: GASES → BARRAS
    # ----------------------------
    if colecao == "gases":
        texto_rel.insert(tk.END, f"Gás selecionado: {codigo}\n\n")
        texto_rel.insert(tk.END, "TAGS relacionadas:\n\n")

        encontrou = False

        if "barras" in data:
            for tag, info in data["barras"].items():
                if isinstance(info, dict):
                    if "codigo" in info and str(info["codigo"]) == str(codigo):
                        texto_rel.insert(tk.END, f"TAG: {tag}\n")
                        encontrou = True

        if not encontrou:
            texto_rel.insert(tk.END, "Nenhuma TAG encontrada.")

    # ----------------------------
    # CASO 2: BARRAS → GASES
    # ----------------------------
    elif colecao == "barras":
        texto_rel.insert(tk.END, f"TAG selecionada: {codigo}\n\n")

        info = data["barras"].get(codigo, {})

        if isinstance(info, dict) and "codigo" in info:
            cod_gas = str(info["codigo"])

            texto_rel.insert(tk.END, f"Código relacionado: {cod_gas}\n\n")

            if "gases" in data and cod_gas in data["gases"]:
                gas = data["gases"][cod_gas]

                texto_rel.insert(tk.END, "Detalhes do gás:\n\n")
                texto_rel.insert(
                    tk.END,
                    json.dumps(gas, indent=2, ensure_ascii=False)
                )
            else:
                texto_rel.insert(tk.END, "Gás não encontrado.")
        else:
            texto_rel.insert(tk.END, "TAG sem código associado.")

    else:
        texto_rel.insert(
            tk.END,
            "Relações disponíveis apenas entre 'gases' e 'barras'."
        )

# ----------------------------
# Exportar Excel
# ----------------------------
def exportar():
    if not data:
        return

    caminho = filedialog.asksaveasfilename(defaultextension=".xlsx")

    rows = []

    for colecao, itens in data.items():
        for codigo, info in itens.items():
            row = {"colecao": colecao, "codigo": codigo}
            if isinstance(info, dict):
                row.update(info)
            rows.append(row)

    df = pd.DataFrame(rows)
    df.to_excel(caminho, index=False)

    messagebox.showinfo("Sucesso", "Arquivo exportado!")


# ----------------------------
# Interface
# ----------------------------
root = tk.Tk()
root.title("Explorador de JSON")
root.geometry("1000x600")

# Botões topo
frame_topo = tk.Frame(root)
frame_topo.pack(fill="x")

tk.Button(frame_topo, text="Carregar JSON", command=carregar_json).pack(side="left")

entry_busca = tk.Entry(frame_topo)
entry_busca.pack(side="left", padx=5)

tk.Button(frame_topo, text="Buscar", command=buscar).pack(side="left")
tk.Button(frame_topo, text="Relações", command=relacoes).pack(side="left")
tk.Button(frame_topo, text="Exportar Excel", command=exportar).pack(side="left")

# Layout principal
frame_main = tk.Frame(root)
frame_main.pack(fill="both", expand=True)

# Árvore
tree = ttk.Treeview(frame_main)
tree.pack(side="left", fill="both", expand=True)
tree.bind("<<TreeviewSelect>>", mostrar_detalhes)

# Painel direito
frame_right = tk.Frame(frame_main)
frame_right.pack(side="right", fill="both", expand=True)

# Detalhes
texto = tk.Text(frame_right, height=15)
texto.pack(fill="both", expand=True)

# Resultados busca
resultado = tk.Text(frame_right, height=10)
resultado.pack(fill="both", expand=True)

root.mainloop()
