	git checkout master &&
	git log --raw --graph --oneline -m master | head -n 500 >actual &&
	git diff-tree --graph master^ | head -n 500 >actual &&
*   commit master
* | commit master~1
* | commit master~2
* | commit master~3
* | commit master~4
	git merge master~3 &&
	git checkout master &&
	git checkout master &&
	git checkout master &&
	git checkout master &&
| * \   Merge branch 'master' (early part) into tangle
	Merge-tag-reach (HEAD -> master)
	Merge-tag-reach (HEAD -> master)
	Merge-tag-reach (HEAD -> master)
	Merge-tag-reach (master)
	Merge-tag-reach (master)
	Merge-tag-reach (HEAD -> master)
| | | |     Merge branch 'master' (early part) into tangle
*** | | | |     Merge branch 'master' (early part) into tangle
	test_when_finished "git reset --hard && git checkout master" &&
	git checkout -b signed master &&
	test_when_finished "git reset --hard && git checkout master" &&
	git checkout -b signed-subkey master &&
	test_when_finished "git reset --hard && git checkout master" &&
	git checkout -b signed-x509 master &&
	test_when_finished "git reset --hard && git checkout master" &&
	git checkout -b plain master &&
	git checkout -b tagged master &&
	test_when_finished "git reset --hard && git checkout master" &&
	git checkout -b plain-shallow master &&
	git checkout --detach master &&
	test_when_finished "git reset --hard && git checkout master" &&
	git checkout -b plain-nokey master &&
	git checkout -b tagged-nokey master &&
	test_when_finished "git reset --hard && git checkout master" &&
	git checkout -b plain-bad master &&
	git checkout -b tagged-bad master &&
	test_when_finished "git reset --hard && git checkout master" &&
	git checkout -b plain-fail master &&
	git checkout -b tagged-fail master &&
	test_when_finished "git reset --hard && git checkout master" &&
	git checkout -b plain-x509 master &&
	git checkout -b tagged-x509 master &&
	test_when_finished "git reset --hard && git checkout master" &&
	git checkout -b plain-x509-nokey master &&
	git checkout -b tagged-x509-nokey master &&
	test_when_finished "git reset --hard && git checkout master" &&
	git checkout -b plain-x509-bad master &&
	git checkout -b tagged-x509-bad master &&
	echo 1234abcd >empty/.git/refs/heads/master &&