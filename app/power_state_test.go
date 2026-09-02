package main

import "testing"

func TestParsePriorPower(t *testing.T) {
	cases := []struct {
		name          string
		content       string
		wantHibernate string
		wantHiberboot string
	}{
		{
			name:          "both enabled",
			content:       "hibernate=1\nhiberboot=1\n",
			wantHibernate: "1",
			wantHiberboot: "1",
		},
		{
			name:          "both disabled",
			content:       "hibernate=0\nhiberboot=0\n",
			wantHibernate: "0",
			wantHiberboot: "0",
		},
		{
			name:          "mixed",
			content:       "hibernate=1\nhiberboot=0\n",
			wantHibernate: "1",
			wantHiberboot: "0",
		},
		{
			name:          "empty input",
			content:       "",
			wantHibernate: "",
			wantHiberboot: "",
		},
		{
			name:          "whitespace and comments",
			content:       "\n  hibernate = 1 \n\nhiberboot = 0\n# comment\n",
			wantHibernate: "1",
			wantHiberboot: "0",
		},
		{
			name:          "substring protection",
			content:       "hibernate=10\nhiberboot=100\n",
			wantHibernate: "10",
			wantHiberboot: "100",
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			gotHib, gotHbb := parsePriorPower(tc.content)
			if gotHib != tc.wantHibernate {
				t.Errorf("parsePriorPower hibernate = %q, want %q", gotHib, tc.wantHibernate)
			}
			if gotHbb != tc.wantHiberboot {
				t.Errorf("parsePriorPower hiberboot = %q, want %q", gotHbb, tc.wantHiberboot)
			}
		})
	}
}
