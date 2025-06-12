import { ImapFlow } from 'imapflow';
import {  loadImapConfig } from './config.js';
import consola from 'consola';

const imapConfig = await loadImapConfig().catch((error) => {
    consola.error("Error loading IMAP config:", error.message);
    process.exit(1);
});

const imapClient = new ImapFlow({
    host: imapConfig.imapHost,
    port: imapConfig.imapPort,
    secure: imapConfig.imapSecure,
    auth: {
        user: imapConfig.imapUser,
        pass: imapConfig.imapPass
    },
    logger: {
        debug: (object) => consola.withTag("IMAP").debug(object.msg),
        info: (object) => consola.withTag("IMAP").info(object.msg),
        warn: (object) => consola.withTag("IMAP").warn(object.msg),
        error: (object) => consola.withTag("IMAP").error(object.msg)
    }
});

try {
    await imapClient.connect();
    consola.success("Connected to IMAP server");
} catch (error) {
    consola.error("Error connecting to IMAP server:", error.message);
    process.exit(1);
}

const senders = {}

const blocklist = [
    "[Gmail]"
]

const mailboxes = (await imapClient.list()).filter(mailbox => {
    if (blocklist.includes(mailbox.name)) return false;
    if (mailbox.specialUse && mailbox.specialUse !== "\\Inbox") return false;
    return true;
})

const mailboxNames = mailboxes.map(mailbox => mailbox.name);
consola.info("Mailboxes found:");
mailboxNames.forEach(name => {
    consola.info(`- ${name}`);
});

for (const mailbox of mailboxes) {
    consola.info(`Processing mailbox: ${mailbox.name}`);

    await imapClient.mailboxOpen(mailbox.path)
    const messages = imapClient.fetch("1:*", { envelope: true})

    let messageCount = 0;
    for await (const message of messages) {
        messageCount++;
        const sender = message.envelope.from[0].address;
        if (!senders[sender]) {
            senders[sender] = 1;
        } else {
            senders[sender]++;
        }
    }
    consola.info(`Processed ${messageCount} messages in mailbox: ${mailbox.name}`);
}

const sortedSenders = Object.entries(senders).sort((a, b) => b[1] - a[1]);
const topSenders = sortedSenders.slice(0, 10);
consola.box("Top 10 senders:\n" + topSenders.map(([sender, count]) => `  ${sender}: ${count}`).join("\n"))