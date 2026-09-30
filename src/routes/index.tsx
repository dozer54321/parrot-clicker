import { createFileRoute } from "@tanstack/react-router";
import { ParrotGame } from "@/components/parrot-game";

export const Route = createFileRoute("/")({ component: Home });

function Home() {
  return <ParrotGame />;
}
