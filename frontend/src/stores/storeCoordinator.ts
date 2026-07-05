type ClearHandler = () => void;

let clearErrors: ClearHandler = () => {};
let clearNotification: ClearHandler = () => {};

export const registerErrorMessageStoreClear = (handler: ClearHandler) => {
    clearErrors = handler;
};

export const registerNotificationStoreClear = (handler: ClearHandler) => {
    clearNotification = handler;
};

export const clearErrorMessagesFromStoreCoordinator = () => {
    clearErrors();
};

export const clearNotificationFromStoreCoordinator = () => {
    clearNotification();
};
