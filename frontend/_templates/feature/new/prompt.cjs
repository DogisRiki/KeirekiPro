module.exports = {
    prompt: ({ inquirer }) => {
        const questions = [
            {
                type: "input",
                name: "name",
                message: "features配下に作成するディレクトリ名を入力してください:",
            },
        ];
        return inquirer.prompt(questions);
    },
};
