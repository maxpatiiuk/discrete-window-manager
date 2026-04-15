import { bindStatus } from "./status";

console.log("Phoenix is running!!");

bindStatus();

Key.on("z", ["alt"], () => {
  console.log("Alt+Z was pressed!");
});

Key.on("r", ["alt", "shift"], () => {
  Phoenix.reload();
});
