// email service for sending auth emails using Resend

import { Resend } from 'resend'
import env from '../config/env.js'

import ConfirmEmailTemplate from './email-templates/ConfirmEmail.js'
import ResetPasswordTemplate from './email-templates/ResetPassword.js'

const resend = new Resend(env.resendApiKey) // create a new resend client

// email verification code, six digit code

type SendEmailVerificationCodeParams = {
    email: string
    code: string
    expiresInMinutes: number
}

type SendResetPasswordEmailParams = {
    email: string
    link: string
    expiresInMinutes: number
}

export async function sendEmailVerificationCode({
    email,
    code,
    expiresInMinutes,
}: SendEmailVerificationCodeParams) {
    const { data, error } = await resend.emails.send({
        from: 'Niche Music <no-reply@auth.nichemusic.app>',
        to: email,
        subject: 'Confirm your Email',
        react: ConfirmEmailTemplate({ email, code, expiresInMinutes }),
    })

    if (error) {
        throw new Error(error.message)
    }

    if (!data) {
        throw new Error('Failed to send email')
    }

    return { id: data.id }
}


export async function sendResetPasswordEmail({
    email,
    link,
    expiresInMinutes,
}: SendResetPasswordEmailParams) {
    const { data, error } = await resend.emails.send({
        from: 'Niche Music <no-reply@auth.nichemusic.app>',
        to: email,
        subject: 'Reset your Password',
        react: ResetPasswordTemplate({ email, link, expiresInMinutes }),
    })

    if (error) {
        throw new Error(error.message)
    }

    if (!data) {
        throw new Error('Failed to send email')
    }

    return { id: data.id }
}