## 6.1.5+1 - 2025-08-19

Updated Discord link.

## 6.1.5 - 2025-04-29

Fix a bug where a bug reading another provider may obtain the wrong value.

## 6.1.4 - 2025-03-27

Fix `MultiProvider` not being inheritable anymore due to 6.1.3.

## 6.1.3 - 2025-03-26 (retracted)

- Significantly increase the number of providers that MultiProvider can create at once without causing a `StackOverflow`.

## 6.1.2 - 2024-02-28

- Fixed an issue with `Selector` not rebuilding when the `builder` listens
  to InheritedWidgets (thanks to @spkersten)
