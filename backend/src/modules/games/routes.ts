import { FastifyPluginAsync } from "fastify"
import { ZodError } from "zod"
import { supabase } from "../../config/supabase.js"
import { sendError, sendSuccess } from "../../global/response.js"
import { generateRandomId } from "../../lib/auth.js"
import {
    AuxBattleError,
    castVote,
    createAuxRoom,
    createBracket,
    createRematch,
    createRoomSchema,
    getRoomState,
    joinAuxRoomByCode,
    joinAuxRoomById,
    joinByCodeSchema,
    leaveAuxRoom,
    markPlayAgain,
    revealMatchup,
    startBracket,
    startMatchupA,
    startMatchupB,
    startSubmissions,
    startVoting,
    submitSong,
    submitSongSchema,
    updateAuxRoomSettings,
    updateRoomSettingsSchema,
    voteSchema,
} from "./service.js"

function handleAuxError(res: Parameters<typeof sendError>[0], err: unknown) {
    if (err instanceof AuxBattleError) {
        return sendError(res, err.code, err.message, err.status)
    }
    if (err instanceof ZodError) {
        return sendError(res, "VALIDATION_ERROR", err.issues[0]?.message ?? "Invalid input", 400)
    }
    throw err
}

const gamesRoutes: FastifyPluginAsync = async (app) => {

    // daily trivia

    app.get('/games/trivia/today', { preHandler: app.authenticate }, async (req, res) => {
        const today = new Date().toISOString().split('T')[0]

        const { data: question, error } = await supabase
            .schema('public')
            .from('daily_trivia_questions')
            .select('id, question_date, question, choices, release_at, correct_choice_id, explanation, question_image_url, explanation_image_url')
            .eq('question_date', today)
            .lte('release_at', new Date().toISOString())
            .maybeSingle()

        if (error || !question) {
            return sendError(res, 'QUESTION_NOT_FOUND', 'Question not found', 404)
        }

        const { data: existingResponse } = await supabase
            .schema('public')
            .from('daily_trivia_responses')
            .select('id, selected_choice_id, is_correct, answered_at')
            .eq('question_id', question.id)
            .eq('user_id', req.userId)
            .maybeSingle()

        const questionPayload = {
            id: question.id,
            question_date: question.question_date,
            question: question.question,
            choices: question.choices,
            release_at: question.release_at,
            question_image_url: question.question_image_url,
        }

        if (existingResponse) {
            return sendSuccess(res, {
                question: questionPayload,
                hasAnswered: true,
                userResponse: existingResponse,
                correctChoiceId: question.correct_choice_id,
                explanation: question.explanation,
                explanationImageUrl: question.explanation_image_url,
            })
        }

        return sendSuccess(res, {
            question: questionPayload,
            hasAnswered: false,
            userResponse: null,
            correctChoiceId: null,
            explanation: null,
            explanationImageUrl: null,
        })
    })

    app.post('/games/trivia/:questionId/answer', { preHandler: app.authenticate }, async (req, res) => {
        const { questionId } = req.params as { questionId: string }
        const body = req.body as { answerId?: number; answer_id?: number }
        const answerId = body.answerId ?? body.answer_id

        if (answerId == null || !Number.isInteger(answerId)) {
            return sendError(res, 'INVALID_ANSWER', 'answerId is required', 400)
        }

        const { data: question, error: questionError } = await supabase
            .schema('public')
            .from('daily_trivia_questions')
            .select('*')
            .eq('id', questionId)
            .lte('release_at', new Date().toISOString())
            .maybeSingle()

        if (questionError || !question) {
            return sendError(res, 'QUESTION_NOT_FOUND', 'Question not found', 404)
        }

        const { data: existingResponse } = await supabase
            .schema('public')
            .from('daily_trivia_responses')
            .select('id, selected_choice_id, is_correct, answered_at')
            .eq('question_id', questionId)
            .eq('user_id', req.userId)
            .maybeSingle()

        if (existingResponse) {
            return sendSuccess(res, {
                correct: existingResponse.is_correct,
                correctChoiceId: question.correct_choice_id,
                explanation: question.explanation,
                explanationImageUrl: question.explanation_image_url,
                response: existingResponse,
                alreadyAnswered: true,
            })
        }

        const isCorrect = question.correct_choice_id === answerId

        const { data: response, error: responseError } = await supabase
            .schema('public')
            .from('daily_trivia_responses')
            .insert({
                id: generateRandomId(16),
                question_id: questionId,
                user_id: req.userId,
                selected_choice_id: answerId,
                is_correct: isCorrect,
                answered_at: new Date().toISOString(),
            })
            .select()
            .single()

        if (responseError) {
            const { data: racedResponse } = await supabase
                .schema('public')
                .from('daily_trivia_responses')
                .select('id, selected_choice_id, is_correct, answered_at')
                .eq('question_id', questionId)
                .eq('user_id', req.userId)
                .maybeSingle()

            if (racedResponse) {
                return sendSuccess(res, {
                    correct: racedResponse.is_correct,
                    correctChoiceId: question.correct_choice_id,
                    explanation: question.explanation,
                    explanationImageUrl: question.explanation_image_url,
                    response: racedResponse,
                    alreadyAnswered: true,
                })
            }

            return sendError(res, 'ANSWER_SUBMIT_FAILED', responseError.message, 400)
        }

        return sendSuccess(res, {
            correct: isCorrect,
            correctChoiceId: question.correct_choice_id,
            explanation: question.explanation,
            explanationImageUrl: question.explanation_image_url,
            response,
            alreadyAnswered: false,
        })
    })


    // aux battles

    app.post('/games/aux/rooms/create', { preHandler: app.authenticate }, async (req, res) => {
        try {
            const input = createRoomSchema.parse(req.body)
            const room = await createAuxRoom(req.userId, input)
            return sendSuccess(res, room, undefined, 201)
        } catch (err) {
            return handleAuxError(res, err)
        }
    })

    app.post('/games/aux/rooms/join', { preHandler: app.authenticate }, async (req, res) => {
        try {
            const { code } = joinByCodeSchema.parse(req.body)
            const room = await joinAuxRoomByCode(req.userId, code)
            return sendSuccess(res, room)
        } catch (err) {
            return handleAuxError(res, err)
        }
    })

    app.post('/games/aux/rooms/:roomId/join', { preHandler: app.authenticate }, async (req, res) => {
        try {
            const { roomId } = req.params as { roomId: string }
            const room = await joinAuxRoomById(req.userId, roomId)
            return sendSuccess(res, room)
        } catch (err) {
            return handleAuxError(res, err)
        }
    })

    app.get('/games/aux/rooms/:roomId', { preHandler: app.authenticate }, async (req, res) => {
        try {
            const { roomId } = req.params as { roomId: string }
            const room = await getRoomState(roomId, req.userId)
            return sendSuccess(res, room)
        } catch (err) {
            return handleAuxError(res, err)
        }
    })

    app.post('/games/aux/rooms/:roomId/leave', { preHandler: app.authenticate }, async (req, res) => {
        try {
            const { roomId } = req.params as { roomId: string }
            const result = await leaveAuxRoom(req.userId, roomId)
            return sendSuccess(res, result)
        } catch (err) {
            return handleAuxError(res, err)
        }
    })

    app.post('/games/aux/rooms/:roomId/settings', { preHandler: app.authenticate }, async (req, res) => {
        try {
            const { roomId } = req.params as { roomId: string }
            const input = updateRoomSettingsSchema.parse(req.body)
            const room = await updateAuxRoomSettings(req.userId, roomId, input)
            return sendSuccess(res, room)
        } catch (err) {
            return handleAuxError(res, err)
        }
    })

    app.post('/games/aux/rooms/:roomId/start-submissions', { preHandler: app.authenticate }, async (req, res) => {
        try {
            const { roomId } = req.params as { roomId: string }
            const room = await startSubmissions(req.userId, roomId)
            return sendSuccess(res, room)
        } catch (err) {
            return handleAuxError(res, err)
        }
    })

    app.post('/games/aux/rooms/:roomId/submit-song', { preHandler: app.authenticate }, async (req, res) => {
        try {
            const { roomId } = req.params as { roomId: string }
            const input = submitSongSchema.parse(req.body)
            const room = await submitSong(req.userId, roomId, input)
            return sendSuccess(res, room)
        } catch (err) {
            return handleAuxError(res, err)
        }
    })

    app.post('/games/aux/rooms/:roomId/bracket/create', { preHandler: app.authenticate }, async (req, res) => {
        try {
            const { roomId } = req.params as { roomId: string }
            const room = await createBracket(req.userId, roomId)
            return sendSuccess(res, room)
        } catch (err) {
            return handleAuxError(res, err)
        }
    })

    app.post('/games/aux/rooms/:roomId/bracket/start', { preHandler: app.authenticate }, async (req, res) => {
        try {
            const { roomId } = req.params as { roomId: string }
            const room = await startBracket(req.userId, roomId)
            return sendSuccess(res, room)
        } catch (err) {
            return handleAuxError(res, err)
        }
    })

    app.post('/games/aux/rooms/:roomId/matchups/:matchupId/start-a', { preHandler: app.authenticate }, async (req, res) => {
        try {
            const { roomId, matchupId } = req.params as { roomId: string; matchupId: string }
            const room = await startMatchupA(req.userId, roomId, matchupId)
            return sendSuccess(res, room)
        } catch (err) {
            return handleAuxError(res, err)
        }
    })

    app.post('/games/aux/rooms/:roomId/matchups/:matchupId/start-b', { preHandler: app.authenticate }, async (req, res) => {
        try {
            const { roomId, matchupId } = req.params as { roomId: string; matchupId: string }
            const room = await startMatchupB(req.userId, roomId, matchupId)
            return sendSuccess(res, room)
        } catch (err) {
            return handleAuxError(res, err)
        }
    })

    app.post('/games/aux/rooms/:roomId/matchups/:matchupId/start-voting', { preHandler: app.authenticate }, async (req, res) => {
        try {
            const { roomId, matchupId } = req.params as { roomId: string; matchupId: string }
            const room = await startVoting(req.userId, roomId, matchupId)
            return sendSuccess(res, room)
        } catch (err) {
            return handleAuxError(res, err)
        }
    })

    app.post('/games/aux/rooms/:roomId/matchups/:matchupId/vote', { preHandler: app.authenticate }, async (req, res) => {
        try {
            const { roomId, matchupId } = req.params as { roomId: string; matchupId: string }
            const { submissionId } = voteSchema.parse(req.body)
            const room = await castVote(req.userId, roomId, matchupId, submissionId)
            return sendSuccess(res, room)
        } catch (err) {
            return handleAuxError(res, err)
        }
    })

    app.post('/games/aux/rooms/:roomId/matchups/:matchupId/reveal', { preHandler: app.authenticate }, async (req, res) => {
        try {
            const { roomId, matchupId } = req.params as { roomId: string; matchupId: string }
            const room = await revealMatchup(req.userId, roomId, matchupId)
            return sendSuccess(res, room)
        } catch (err) {
            return handleAuxError(res, err)
        }
    })

    app.post('/games/aux/rooms/:roomId/play-again', { preHandler: app.authenticate }, async (req, res) => {
        try {
            const { roomId } = req.params as { roomId: string }
            const room = await markPlayAgain(req.userId, roomId)
            return sendSuccess(res, room)
        } catch (err) {
            return handleAuxError(res, err)
        }
    })

    app.post('/games/aux/rooms/:roomId/rematch/create', { preHandler: app.authenticate }, async (req, res) => {
        try {
            const { roomId } = req.params as { roomId: string }
            const result = await createRematch(req.userId, roomId)
            return sendSuccess(res, result, undefined, 201)
        } catch (err) {
            return handleAuxError(res, err)
        }
    })
}

export default gamesRoutes
