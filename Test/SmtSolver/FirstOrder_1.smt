(set-option :produce-proofs true)
(assert (|not| |false|))
(declare-sort |smti_0| 0)
(declare-fun |smti_1| () |smti_0|)
(assert (forall ((|smtd_1| |smti_0|)) (|=| |smtd_1| |smti_1|)))
(check-sat)
(get-model)