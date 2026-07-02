import React from 'react'

const colors = {
    bg: '#050505',
    text: '#f4f1ea',
    muted: 'rgba(244, 241, 234, 0.68)',
    line: 'rgba(244, 241, 234, 0.18)',
    accent: '#962a72',
} as const

type ConfirmEmailTemplateProps = {
    email: string
    code: string
    expiresInMinutes: number
}

function formatCode(code: string): string {
    const digits = code.replace(/\D/g, '').slice(0, 6)
    if (digits.length <= 3) return digits
    return `${digits.slice(0, 3)} ${digits.slice(3)}`
}

function expiryLabel(minutes: number): string {
    if (minutes === 1) return '1 minute'
    return `${minutes} minutes`
}

export default function ConfirmEmailTemplate({
    email,
    code,
    expiresInMinutes,
}: ConfirmEmailTemplateProps) {
    const formattedCode = formatCode(code)
    const expiry = expiryLabel(expiresInMinutes)

    return (
        <html lang="en">
            <head>
                <meta charSet="utf-8" />
                <meta name="viewport" content="width=device-width, initial-scale=1.0" />
                <meta name="color-scheme" content="dark" />
                <meta name="supported-color-schemes" content="dark" />
                <title>Verify your email — Niche Music</title>
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
                    Your verification code is {formattedCode}. It expires in {expiry}.
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
                                                    Email verification
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
                                                    Enter this code in the app to verify{' '}
                                                    <span style={{ color: colors.text }}>{email}</span>.
                                                </p>

                                                <div
                                                    style={{
                                                        border: `1px solid ${colors.line}`,
                                                        borderLeft: `3px solid ${colors.accent}`,
                                                        padding: '28px 24px',
                                                        marginBottom: '24px',
                                                        textAlign: 'center',
                                                        backgroundColor: 'rgba(244, 241, 234, 0.025)',
                                                    }}
                                                >
                                                    <p
                                                        style={{
                                                            margin: '0 0 10px',
                                                            fontSize: '13px',
                                                            lineHeight: '1',
                                                            letterSpacing: '0.08em',
                                                            textTransform: 'uppercase',
                                                            color: colors.muted,
                                                        }}
                                                    >
                                                        Your code
                                                    </p>
                                                    <p
                                                        style={{
                                                            margin: 0,
                                                            fontSize: '40px',
                                                            lineHeight: '1',
                                                            letterSpacing: '0.22em',
                                                            fontWeight: 500,
                                                            fontFamily:
                                                                'ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, monospace',
                                                            color: colors.text,
                                                        }}
                                                    >
                                                        {formattedCode}
                                                    </p>
                                                </div>

                                                <p
                                                    style={{
                                                        margin: '0 0 28px',
                                                        fontSize: '15px',
                                                        lineHeight: '1.5',
                                                        color: colors.muted,
                                                    }}
                                                >
                                                    This code expires in{' '}
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
                                                    If you did not request this, you can ignore this email.
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
