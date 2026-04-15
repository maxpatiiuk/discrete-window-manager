# Discrete window manager - Phoenix

This was an attempt to implement a discrete window manager using [Phoenix](https://github.com/kasper/phoenix).

Phoenix has a nice idea - they provide a higher level wrapper over objective-c apis, letting you write the logic in JavaScript. Since it is JavaScript, you can use Vite, TypeScript, and other modern tooling.

However, I didn't get far. Blockers:

- Phoenix executes JavaScript in a limited JavaScriptCore VM - it doesn't have access to the file system or even `performance.now()` to evaluate the performance.
- Performance degrades quickly for even relatively simple use cases (displaying a list of all open windows, their space, and screen). This is likely because of two causes:
  - Serialization overhead between objective-c and JavaScript
  - Phoenix's API doesn't document how expensive the APIs are and doesn't expose lower level or batch APIs.
