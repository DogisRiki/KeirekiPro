import TextInput from "@/TextInput";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";

test("TextInput Component test", () => {
    render(<TextInput />);

    const inputElement = screen.getByRole("textbox");
    expect(inputElement).toBeInTheDocument();
});

test("TextInput Event Test", async () => {
    const user = userEvent.setup();
    render(<TextInput />);

    const inputElement = screen.getByRole("textbox");
    await user.type(inputElement, "Vitest Test!");
    expect(screen.getByText("Vitest Test!")).toBeInTheDocument();
});
