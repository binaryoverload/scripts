import { ImapFlow } from 'imapflow';
import { input, number, password, confirm } from "@inquirer/prompts"
import { consola } from "consola";
import dotenv from 'dotenv';
import { writeFile } from "fs/promises"

dotenv.config();

export async function loadImapConfig() {
    const validKeys = [
        "IMAP_HOST",
        "IMAP_PORT",
        "IMAP_SECURE",
        "IMAP_USERNAME",
        "IMAP_PASSWORD"
    ]

    const imapKeys = Object.entries(process.env).filter(([key]) => validKeys.includes(key)).reduce((acc, [key, value]) => ({
        ...acc,
        [key]: value
    }), {});

    if (Object.keys(imapKeys).length !== 0) {
        consola.withTag("Config").info("Using IMAP credentials from environment variables:");
        Object.entries(imapKeys).forEach(([key, value]) => {
            if (key === "IMAP_PASSWORD") {
                value = "********";
            }
            consola.withTag("Config").info(`- ${key}: ${value}`);
        });
    }

    let imapHost = process.env.IMAP_HOST;
    let imapPort = Number(process.env.IMAP_PORT);
    let imapSecure = Boolean(process.env.IMAP_SECURE);
    let imapUser = process.env.IMAP_USERNAME;
    let imapPass = process.env.IMAP_PASSWORD;

    let configChanged = false;

    if (!imapHost) {
        imapHost = await input({
            message: "Enter your IMAP host"
        });
        configChanged = true;
    }

    if (!imapPort) {
        imapPort = await number({
            message: "Enter your IMAP port",
            validate: (value) => {
                if (isNaN(value)) {
                    return "Please enter a valid number";
                }
                return true;
            }
        });
        configChanged = true;
    }

    if (!imapSecure) {
        imapSecure = await confirm({
            message: "Use TLS for IMAP connection?",
            initial: true
        });
        configChanged = true;
    }

    if (!imapUser) {
        imapUser = await input({
            message: "Enter your IMAP username"
        });
        configChanged = true;
    }

    if (!imapPass) {
        imapPass = await password({
            message: "Enter your IMAP password",
            type: "password",
            mask: true
        });
        configChanged = true;
    }

    if (configChanged) {
        const saveConfig = await confirm({
            message: "Do you want to save these credentials for future use?",
            initial: false
        });

        if (saveConfig) {
            const config = {
                IMAP_HOST: imapHost,
                IMAP_PORT: imapPort,
                IMAP_SECURE: imapSecure,
                IMAP_USERNAME: imapUser,
                IMAP_PASSWORD: imapPass
            };

            await writeFile('.env', Object.entries(config).map(([key, value]) => `${key}=${value}`).join('\n'));
            consola.withTag("Config").success("Credentials saved to .env file");
        }
    }

    return {
        imapHost,
        imapPort,
        imapSecure,
        imapUser,
        imapPass
    };
}