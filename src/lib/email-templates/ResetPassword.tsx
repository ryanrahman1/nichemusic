import React from 'react'

const colors = {
    bg: '#050505',
    text: '#f4f1ea',
    muted: 'rgba(244, 241, 234, 0.68)',
    line: 'rgba(244, 241, 234, 0.18)',
    accent: '#962a72',
} as const

type ResetPasswordTemplateProps = {
    email: string
    link: string
    expiresInMinutes: number
}

function expiryLabel(minutes: number): string {
    if (minutes === 1) return '1 minute'
    return `${minutes} minutes`
}

export default function ResetPasswordTemplate({
    email,
    link,
    expiresInMinutes,
}: ResetPasswordTemplateProps) {
    const expiry = expiryLabel(expiresInMinutes)

    return (
        <html lang="en">
            <head>
                <meta charSet="utf-8" />
                <meta name="viewport" content="width=device-width, initial-scale=1.0" />
                <meta name="color-scheme" content="dark" />
                <meta name="supported-color-schemes" content="dark" />
                <title>Reset your password — Niche Music</title>
            </head>
            <body
                style={{
                    margin: 0,
                    padding: 0,
                    backgroundColor: colors.bg,
                    color: colors.text,
                    fontFamily:
                        '-apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif',
                    WebkitFontSmoothing: 'antialiased',
                }}
            >
                <div
                    style={{
                        display: 'none',
                        maxHeight: 0,
                        overflow: 'hidden',
                        opacity: 0,
                    }}
                >
                    Reset your Niche Music password: {link}. This link expires in {expiry}.
                </div>

                <table
                    role="presentation"
                    width="100%"
                    cellPadding={0}
                    cellSpacing={0}
                    style={{ backgroundColor: colors.bg }}
                >
                    <tbody>
                        <tr>
                            <td align="center" style={{ padding: '48px 20px' }}>
                                <table
                                    role="presentation"
                                    width="100%"
                                    cellPadding={0}
                                    cellSpacing={0}
                                    style={{
                                        maxWidth: '520px',
                                        borderTop: `1px solid ${colors.line}`,
                                        borderBottom: `1px solid ${colors.line}`,
                                    }}
                                >
                                    <tbody>
                                        <tr>
                                            <td style={{ padding: '40px 28px 32px' }}>
                                                <p
                                                    style={{
                                                        margin: '0 0 28px',
                                                        fontSize: '14px',
                                                        lineHeight: '1',
                                                        letterSpacing: '-0.02em',
                                                        color: colors.accent,
                                                    }}
                                                >
                                                    Password reset
                                                </p>

                                                <h1
                                                    style={{
                                                        margin: '0 0 16px',
                                                        fontSize: '36px',
                                                        lineHeight: '0.92',
                                                        letterSpacing: '-0.06em',
                                                        fontWeight: 500,
                                                        color: colors.text,
                                                    }}
                                                >
                                                    Niche Music
                                                    <span style={{ color: colors.accent }}>.</span>
                                                </h1>

                                                <p
                                                    style={{
                                                        margin: '0 0 32px',
                                                        fontSize: '17px',
                                                        lineHeight: '1.45',
                                                        color: colors.muted,
                                                    }}
                                                >
                                                    We received a request to reset the password for{' '}
                                                    <span style={{ color: colors.text }}>{email}</span>.
                                                    Tap the button below to choose a new one.
                                                </p>

                                                <table
                                                    role="presentation"
                                                    width="100%"
                                                    cellPadding={0}
                                                    cellSpacing={0}
                                                    style={{ marginBottom: '28px' }}
                                                >
                                                    <tbody>
                                                        <tr>
                                                            <td align="center">
                                                                <a
                                                                    href={link}
                                                                    style={{
                                                                        display: 'inline-block',
                                                                        padding: '16px 32px',
                                                                        backgroundColor: colors.accent,
                                                                        color: colors.text,
                                                                        fontSize: '16px',
                                                                        fontWeight: 500,
                                                                        lineHeight: '1',
                                                                        letterSpacing: '-0.02em',
                                                                        textDecoration: 'none',
                                                                        borderRadius: '999px',
                                                                    }}
                                                                >
                                                                    Reset password
                                                                </a>
                                                            </td>
                                                        </tr>
                                                    </tbody>
                                                </table>

                                                <div
                                                    style={{
                                                        border: `1px solid ${colors.line}`,
                                                        borderLeft: `3px solid ${colors.accent}`,
                                                        padding: '20px 24px',
                                                        marginBottom: '24px',
                                                        backgroundColor: 'rgba(244, 241, 234, 0.025)',
                                                    }}
                                                >
                                                    <p
                                                        style={{
                                                            margin: '0 0 10px',
                                                            fontSize: '13px',
                                                            lineHeight: '1.4',
                                                            letterSpacing: '0.04em',
                                                            textTransform: 'uppercase',
                                                            color: colors.muted,
                                                        }}
                                                    >
                                                        Or copy this link
                                                    </p>
                                                    <a
                                                        href={link}
                                                        style={{
                                                            margin: 0,
                                                            fontSize: '14px',
                                                            lineHeight: '1.5',
                                                            wordBreak: 'break-all',
                                                            color: colors.text,
                                                            textDecoration: 'underline',
                                                            textUnderlineOffset: '3px',
                                                        }}
                                                    >
                                                        {link}
                                                    </a>
                                                </div>

                                                <p
                                                    style={{
                                                        margin: '0 0 28px',
                                                        fontSize: '15px',
                                                        lineHeight: '1.5',
                                                        color: colors.muted,
                                                    }}
                                                >
                                                    This link expires in{' '}
                                                    <span style={{ color: colors.text }}>{expiry}</span>.
                                                </p>

                                                <p
                                                    style={{
                                                        margin: 0,
                                                        fontSize: '15px',
                                                        lineHeight: '1.5',
                                                        color: colors.muted,
                                                    }}
                                                >
                                                    If you did not request a password reset, you can safely
                                                    ignore this email. Your password will stay the same.
                                                </p>
                                            </td>
                                        </tr>

                                        <tr>
                                            <td
                                                style={{
                                                    padding: '24px 28px 36px',
                                                    borderTop: `1px solid ${colors.line}`,
                                                }}
                                            >
                                                <p
                                                    style={{
                                                        margin: '0 0 8px',
                                                        fontSize: '18px',
                                                        lineHeight: '1.2',
                                                        letterSpacing: '-0.04em',
                                                        fontWeight: 500,
                                                        color: colors.text,
                                                    }}
                                                >
                                                    Underground music, documented as it happens.
                                                </p>
                                                <p
                                                    style={{
                                                        margin: '0 0 20px',
                                                        fontSize: '14px',
                                                        lineHeight: '1.4',
                                                        color: colors.muted,
                                                    }}
                                                >
                                                    © 2026 Niche Music, LLC
                                                </p>
                                                <p style={{ margin: 0, fontSize: '14px', lineHeight: '1.4' }}>
                                                    <a
                                                        href="mailto:hello@nichemusic.app"
                                                        style={{ color: colors.muted, textDecoration: 'none' }}
                                                    >
                                                        Contact
                                                    </a>
                                                    <span style={{ color: colors.line, margin: '0 10px' }}>·</span>
                                                    <a
                                                        href="https://nichemusic.app/privacy/"
                                                        style={{ color: colors.muted, textDecoration: 'none' }}
                                                    >
                                                        Privacy
                                                    </a>
                                                    <span style={{ color: colors.line, margin: '0 10px' }}>·</span>
                                                    <a
                                                        href="https://nichemusic.app/terms/"
                                                        style={{ color: colors.muted, textDecoration: 'none' }}
                                                    >
                                                        Terms
                                                    </a>
                                                </p>
                                            </td>
                                        </tr>
                                    </tbody>
                                </table>
                            </td>
                        </tr>
                    </tbody>
                </table>
            </body>
        </html>
    )
}
