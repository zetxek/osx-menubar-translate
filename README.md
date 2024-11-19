# README #

MenuBar Translate is a very simple app that lets you have a quick shortcut to Google Translate in your OS X menu bar and integrate it with the OS X "Services" menu. Its main purpose is to allow you to have Google Translate by hand at all times, without needing to open a new browser window.

One click, and you're ready to translate.

![](Docs/service-demo.gif)

You can open the application from your menubar, as well as from OS X contextual service ("Services > Translate in MenuTranslate"):

![2024-11-19 21 32 57](https://github.com/user-attachments/assets/433a4b0c-2f0d-4782-926c-1f7b8c5ace09)

The app has no tracking at all (well, except the one that Google will do on the Translate instance loaded in the embedded WebView - but nothing by me). Code-wise it might also serve you as a blueprint to implement a embedded webview, with a service to receive text from other contexts.

## Supported key shortcuts

- `cmd + a` to **select all**
- `cmd + c` to **copy**
- `cmd + v` to **paste**

## Download

Get the last binary in [the releases section](https://github.com/zetxek/osx-menubar-translate/releases).
Unzip the file, and drag&drop to the Applications folder. Ready!

## Contributing

The project just solves a personal need I have: I am Spanish and live abroad (first in The Netherlands, now in Denmark), so often I need to translate texts or words I don't know yet.

If this project is useful for you and you would like to get it improved, feel free to [create an issue](https://github.com/zetxek/osx-menubar-translate/issues), or [open a PR](https://github.com/zetxek/osx-menubar-translate/pulls) straight away. It will be more than welcome!

## Screenshots
The icon in the menu bar:
![](Resources/closed.png)

The embeded window open:
![](Resources/open.png)

The Finder service integration 
![](Docs/service-demo.gif)


## License

MIT License, available in [license.md](license.md).
