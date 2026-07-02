import { FastifyPluginAsync } from "fastify"
import { supabase } from "../../config/supabase.js"
import { sendError, sendSuccess } from "../../global/response.js"
import { generateRandomId } from "../../lib/auth.js"

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
}

export default gamesRoutes