import flet as ft

async def main(page: ft.Page):
    page.bgcolor = "#ff0000"
    page.add(ft.Text("IT WORKS", size=40, color="white"))
    page.update()

ft.app(target=main)
